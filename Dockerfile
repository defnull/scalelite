FROM ruby:2.7.6-alpine AS base
RUN apk add --no-cache \
    libpq \
    libxml2 \
    libxslt \
    tini \
    tzdata \
    shared-mime-info

RUN addgroup scalelite --gid 1000 && \
    adduser -u 1000 -h /srv/scalelite -G scalelite -D scalelite
RUN addgroup scalelite-spool --gid 2000 && \
    addgroup scalelite scalelite-spool
WORKDIR /srv/scalelite

FROM base as builder
RUN apk add --update --no-cache \
    build-base \
    libxml2-dev \
    libxslt-dev \
    pkgconf \
    postgresql-dev \
    ruby-dev \
    && ( echo 'install: --no-document' ; echo 'update: --no-document' ) >>/etc/gemrc

USER scalelite:scalelite
COPY --chown=scalelite:scalelite Gemfile* ./

RUN bundle config --global frozen 1 \
    && bundle config set deployment 'true' \
    && bundle config set without 'development:test' \
    && bundle install -j4 --path=vendor/bundle \
    && rm -rf vendor/bundle/ruby/*/cache/*.gem \
    && find vendor/bundle/ruby/*/gems/ -name "*.c" -delete \
    && find vendor/bundle/ruby/*/gems/ -name "*.o" -delete

COPY --chown=scalelite:scalelite . ./
RUN rm -rf nginx

FROM base AS application
USER scalelite:scalelite
ENV RAILS_ENV=production RAILS_LOG_TO_STDOUT=true
COPY --from=builder --chown=scalelite:scalelite /srv/scalelite ./

ARG BUILD_NUMBER
ENV BUILD_NUMBER=${BUILD_NUMBER}

FROM application AS recording-importer
ENV RECORDING_IMPORT_POLL=true
CMD [ "bin/start-recording-importer" ]

FROM application AS poller
CMD [ "bin/start-poller" ]

FROM application AS api
EXPOSE 3000
CMD [ "bin/start" ]
