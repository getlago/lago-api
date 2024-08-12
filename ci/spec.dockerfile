FROM ruby:3.3.4-slim

WORKDIR /app

COPY . /app

RUN apt update -qq && apt install nodejs build-essential git pkg-config libpq-dev -y

ENV BUNDLER_VERSION='2.5.5'
RUN gem install bundler --no-document -v '2.5.5'

RUN bundle config build.nokogiri --use-system-libraries &&\
bundle install

CMD ["./scripts/start.dev.sh"]
