ARG PDFCPU_VERSION=0.13.0
ARG GO_VERSION=1.25.11

FROM golang:${GO_VERSION} AS pdfcpu-build

ARG PDFCPU_VERSION

RUN go install github.com/pdfcpu/pdfcpu/cmd/pdfcpu@v${PDFCPU_VERSION}

FROM ruby:4.0.5-slim AS build

ARG BUNDLE_WITH

WORKDIR /app

RUN apt update && apt upgrade -y
RUN apt install nodejs curl build-essential git pkg-config libpq-dev libclang-dev postgresql-client curl libyaml-dev -y && \
  curl https://sh.rustup.rs -sSf | bash -s -- -y

COPY ./Gemfile /app/Gemfile
COPY ./Gemfile.lock /app/Gemfile.lock

ENV BUNDLER_VERSION='4.0.4'
ENV PATH="$PATH:/root/.cargo/bin/"
RUN gem install bundler --no-document -v '4.0.4'

ENV BUNDLE_WITH=${BUNDLE_WITH:-}
ENV BUNDLE_WITHOUT="development test"
RUN --mount=type=secret,id=BUNDLE_GEMS__CONTRIBSYS__COM,env=BUNDLE_GEMS__CONTRIBSYS__COM \
  bundle config set build.nokogiri --use-system-libraries &&\
  bundle install --jobs=3 --retry=3

FROM ruby:4.0.5-slim

ARG BUNDLE_WITH

RUN apt update && apt upgrade -y
RUN apt install git libpq-dev curl postgresql-client -y

# Patch net-imap shipped in the Ruby base image (0.6.2, CVE-2026-42257/42258/42245/42246).
# GEM_HOME is /usr/local/bundle in the base image, so target the Ruby system gem dir
# explicitly, then remove the superseded 0.6.2 so it no longer ships in the image.
ENV RUBY_GEM_DIR=/usr/local/lib/ruby/gems/4.0.0
RUN GEM_HOME=$RUBY_GEM_DIR gem update net-imap && \
  rm -f $RUBY_GEM_DIR/specifications/net-imap-0.6.2.gemspec && \
  rm -rf $RUBY_GEM_DIR/gems/net-imap-0.6.2

ARG SEGMENT_WRITE_KEY
ARG GOCARDLESS_CLIENT_ID
ARG GOCARDLESS_CLIENT_SECRET

ENV SEGMENT_WRITE_KEY=$SEGMENT_WRITE_KEY
ENV GOCARDLESS_CLIENT_ID=$GOCARDLESS_CLIENT_ID
ENV GOCARDLESS_CLIENT_SECRET=$GOCARDLESS_CLIENT_SECRET

ENV BUNDLE_WITH=${BUNDLE_WITH:-}
ENV BUNDLE_WITHOUT="development test"

COPY --from=build /usr/local/bundle/ /usr/local/bundle
COPY --from=pdfcpu-build /go/bin/pdfcpu /usr/local/bin/pdfcpu
WORKDIR /app
COPY . .

CMD ["./scripts/start.sh"]
