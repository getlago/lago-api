ARG PDFCPU_VERSION=0.11.1

FROM ruby:4.0.1-slim AS build

ARG BUNDLE_WITH
ARG PDFCPU_VERSION

WORKDIR /app

RUN apt update && apt upgrade -y
RUN apt install nodejs curl build-essential git pkg-config libpq-dev libclang-dev postgresql-client curl libyaml-dev -y && \
  curl https://sh.rustup.rs -sSf | bash -s -- -y

ARG TARGETARCH
RUN PDFCPU_ARCH=$(case "${TARGETARCH}" in arm64) echo "arm64" ;; *) echo "x86_64" ;; esac) \
  && curl -L "https://github.com/pdfcpu/pdfcpu/releases/download/v${PDFCPU_VERSION}/pdfcpu_${PDFCPU_VERSION}_Linux_${PDFCPU_ARCH}.tar.xz" -o pdfcpu.tar.xz \
  && tar -xf pdfcpu.tar.xz \
  && install -m 755 "pdfcpu_${PDFCPU_VERSION}_Linux_${PDFCPU_ARCH}/pdfcpu" /usr/local/bin/ \
  && rm -rf pdfcpu.tar.xz "pdfcpu_${PDFCPU_VERSION}_Linux_${PDFCPU_ARCH}"

COPY ./Gemfile /app/Gemfile
COPY ./Gemfile.lock /app/Gemfile.lock

ENV BUNDLER_VERSION='2.6.8'
ENV PATH="$PATH:/root/.cargo/bin/"
RUN gem install bundler --no-document -v '2.6.8'

ENV BUNDLE_WITH=${BUNDLE_WITH:-}
ENV BUNDLE_WITHOUT="development test"
RUN --mount=type=secret,id=BUNDLE_GEMS__CONTRIBSYS__COM,env=BUNDLE_GEMS__CONTRIBSYS__COM \
  bundle config set build.nokogiri --use-system-libraries &&\
  bundle install --jobs=3 --retry=3

FROM ruby:4.0.1-slim

ARG BUNDLE_WITH

RUN apt update && apt upgrade -y
RUN apt install git libpq-dev curl postgresql-client -y

ARG SEGMENT_WRITE_KEY
ARG GOCARDLESS_CLIENT_ID
ARG GOCARDLESS_CLIENT_SECRET

ENV SEGMENT_WRITE_KEY=$SEGMENT_WRITE_KEY
ENV GOCARDLESS_CLIENT_ID=$GOCARDLESS_CLIENT_ID
ENV GOCARDLESS_CLIENT_SECRET=$GOCARDLESS_CLIENT_SECRET

ENV BUNDLE_WITH=${BUNDLE_WITH:-}
ENV BUNDLE_WITHOUT="development test"

COPY --from=build /usr/local/bundle/ /usr/local/bundle
COPY --from=build /usr/local/bin/pdfcpu /usr/local/bin/pdfcpu
WORKDIR /app
COPY . .

CMD ["./scripts/start.sh"]
