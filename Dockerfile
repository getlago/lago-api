FROM ruby:3.2.2-slim as build

WORKDIR /app

COPY ./Gemfile /app/Gemfile
COPY ./Gemfile.lock /app/Gemfile.lock

RUN apt update -qq && apt install nodejs build-essential git pkg-config libpq-dev -y

ENV BUNDLER_VERSION='2.4.21'
RUN gem install bundler --no-document -v '2.4.21'

RUN bundle config build.nokogiri --use-system-libraries &&\
  bundle install --jobs=3 --retry=3 --without development test

FROM ruby:3.2.2-slim

WORKDIR /app

COPY . /app

ARG SEGMENT_WRITE_KEY
ARG GOCARDLESS_CLIENT_ID
ARG GOCARDLESS_CLIENT_SECRET

RUN apt update -qq && apt install git libpq-dev -y

ENV SEGMENT_WRITE_KEY $SEGMENT_WRITE_KEY
ENV GOCARDLESS_CLIENT_ID $GOCARDLESS_CLIENT_ID
ENV GOCARDLESS_CLIENT_SECRET $GOCARDLESS_CLIENT_SECRET

COPY --from=build /usr/local/bundle/ /usr/local/bundle

CMD ["./scripts/start.sh"]
