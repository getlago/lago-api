FROM ruby:3.3.4-slim AS build

WORKDIR /app

RUN apt update -qq && apt install nodejs curl build-essential git pkg-config libpq-dev libclang-dev curl -y && \
  curl https://sh.rustup.rs -sSf | bash -s -- -y

COPY ./Gemfile /app/Gemfile
COPY ./Gemfile.lock /app/Gemfile.lock

ENV BUNDLER_VERSION='2.5.5'
ENV PATH="$PATH:/root/.cargo/bin/"
RUN gem install bundler --no-document -v '2.5.5'

RUN bundle config build.nokogiri --use-system-libraries &&\
  bundle install --jobs=3 --retry=3 --without development test

# Temporary fix for mission_control-jobs
# See https://github.com/rails/mission_control-jobs/issues/60#issuecomment-2486452545
COPY . /app
RUN RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

FROM ruby:3.3.4-slim

WORKDIR /app

COPY . /app

ARG SEGMENT_WRITE_KEY
ARG GOCARDLESS_CLIENT_ID
ARG GOCARDLESS_CLIENT_SECRET

RUN apt update -qq && apt install git libpq-dev curl -y

ENV SEGMENT_WRITE_KEY=$SEGMENT_WRITE_KEY
ENV GOCARDLESS_CLIENT_ID=$GOCARDLESS_CLIENT_ID
ENV GOCARDLESS_CLIENT_SECRET=$GOCARDLESS_CLIENT_SECRET

COPY --from=build /usr/local/bundle/ /usr/local/bundle
COPY --from=build /app/public/assets /app/public/assets

CMD ["./scripts/start.sh"]
