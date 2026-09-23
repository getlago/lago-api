# syntax=docker/dockerfile:1
#
# Hardened Wolfi-based build for lago-api, and the only one. Every
# downstream build — staging, production and the OSS release — targets
# this file. The Debian-based `Dockerfile.legacy` it replaced is gone.
#
# Consumes two apko-built bases from https://github.com/getlago/lago-packages.
# Both are public, multi-arch and cosign-signed, so building this file needs no
# registry credentials:
#   - ghcr.io/getlago/lago-api-build:latest  — ruby-4-dev, rust, build-base, node
#   - ghcr.io/getlago/lago-api-base:latest   — ruby-4, jemalloc, libpq, pdfcpu, git
#
# The bases carry no shell history, no apt, no distro cruft; every package
# has an SBOM and is signed. This Dockerfile just bundles gems and copies code.

ARG BUILD_IMAGE=ghcr.io/getlago/lago-api-build:latest
ARG RUNTIME_IMAGE=ghcr.io/getlago/lago-api-base:latest

FROM ${BUILD_IMAGE} AS build

ARG BUNDLE_WITH
ARG BUNDLER_VERSION=4.0.19

USER root
WORKDIR /app

ENV BUNDLE_WITH=${BUNDLE_WITH:-}
ENV BUNDLE_WITHOUT="development test"
ENV BUNDLE_PATH=/usr/local/bundle
ENV GEM_HOME=/usr/local/bundle
ENV PATH=/usr/local/bundle/bin:${PATH}

COPY Gemfile Gemfile.lock ./

RUN gem install bundler --no-document -v "${BUNDLER_VERSION}"

RUN --mount=type=secret,id=BUNDLE_GEMS__CONTRIBSYS__COM,env=BUNDLE_GEMS__CONTRIBSYS__COM \
    bundle config set --local build.nokogiri --use-system-libraries && \
    bundle install --jobs=3 --retry=3

FROM ${RUNTIME_IMAGE}

ARG BUNDLE_WITH
ARG SEGMENT_WRITE_KEY
ARG GOCARDLESS_CLIENT_ID
ARG GOCARDLESS_CLIENT_SECRET

ENV SEGMENT_WRITE_KEY=${SEGMENT_WRITE_KEY}
ENV GOCARDLESS_CLIENT_ID=${GOCARDLESS_CLIENT_ID}
ENV GOCARDLESS_CLIENT_SECRET=${GOCARDLESS_CLIENT_SECRET}

ENV BUNDLE_WITH=${BUNDLE_WITH:-}
ENV BUNDLE_WITHOUT="development test"
ENV BUNDLE_PATH=/usr/local/bundle
ENV GEM_HOME=/usr/local/bundle
ENV PATH=/usr/local/bundle/bin:${PATH}

WORKDIR /app

COPY --from=build --chown=nonroot:nonroot /usr/local/bundle /usr/local/bundle
COPY --chown=nonroot:nonroot . .

USER nonroot

CMD ["/app/scripts/start.sh"]
