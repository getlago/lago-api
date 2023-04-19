FROM ruby:3.2.2-alpine as build

WORKDIR /app

COPY ./Gemfile /app/Gemfile
COPY ./Gemfile.lock /app/Gemfile.lock

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories

RUN apk add --no-cache \
  git \
  bash \
  build-base \
  libxml2-dev \
  libxslt-dev \
  nodejs \
  tzdata \
  openssl \
  postgresql-dev \
  libc6-compat

ENV BUNDLER_VERSION='2.3.26'
RUN gem sources --add https://mirrors.tuna.tsinghua.edu.cn/rubygems/ --remove https://rubygems.org/
RUN bundle config mirror.https://rubygems.org https://mirrors.tuna.tsinghua.edu.cn/rubygems
RUN gem install bundler --no-document -v '2.3.26' --verbose

RUN bundle config build.nokogiri --use-system-libraries &&\
  bundle install --jobs=3 --retry=3 --without development test

FROM ruby:3.2.2-alpine

WORKDIR /app

COPY . /

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories

RUN apk add --no-cache \
  bash \
  postgresql-dev \
  tzdata \
  libc6-compat

ARG SEGMENT_WRITE_KEY
ARG GOCARDLESS_CLIENT_ID
ARG GOCARDLESS_CLIENT_SECRET

ENV SEGMENT_WRITE_KEY $SEGMENT_WRITE_KEY
ENV GOCARDLESS_CLIENT_ID $GOCARDLESS_CLIENT_ID
ENV GOCARDLESS_CLIENT_SECRET $GOCARDLESS_CLIENT_SECRET

COPY --from=build /usr/local/bundle/ /usr/local/bundle

CMD ["./scripts/start.sh"]
