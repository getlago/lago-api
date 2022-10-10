FROM ruby:3.0.1-alpine as build

WORKDIR /app

COPY ./Gemfile /app/Gemfile
COPY ./Gemfile.lock /app/Gemfile.lock

RUN apk add --no-cache \
  git \
  bash \
  build-base \
  libxml2-dev \
  libxslt-dev \
  nodejs \
  python2 \
  tzdata \
  openssl \
  postgresql-dev

RUN bundle config build.nokogiri --use-system-libraries &&\
  bundle install --jobs=3 --retry=3 --without development test

FROM ruby:3.0.1-alpine

WORKDIR /app

COPY . /app

RUN apk add --no-cache \
  bash \
  postgresql-dev \
  tzdata

ARG SEGMENT_WRITE_KEY

ENV SEGMENT_WRITE_KEY $SEGMENT_WRITE_KEY

COPY --from=build /usr/local/bundle/ /usr/local/bundle

CMD ["./scripts/start.sh"]