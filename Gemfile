# frozen_string_literal: true

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.6"

# Core
gem "aasm"
gem "activejob-uniqueness", require: "active_job/uniqueness/sidekiq_patch"
gem "active_storage_validations"
gem "bootsnap", require: false
gem "clockwork", require: false
gem "parallel"
gem "puma", "~> 6.5"
gem "rails", "~> 7.1.5.1"
gem "redis"
gem "sidekiq"
gem "sidekiq-throttled", "1.4.0" # '1.5.0' was losing some jobs
gem "throttling"
gem "dry-validation"

# Security
gem "bcrypt"
gem "googleauth", "~> 1.11.0"
gem "jwt"
gem "oauth2"
gem "rack-cors"

# Database
gem "after_commit_everywhere"
gem "clickhouse-activerecord", "~> 1.2.0"
gem "discard", "~> 1.2"
gem "kaminari-activerecord"
gem "paper_trail"
gem "pg"
gem "ransack"
gem "scenic"
gem "with_advisory_lock"
gem "strong_migrations"

# Currencies, Countries, Timezones...
gem "bigdecimal"
gem "countries"
gem "money-rails"
gem "timecop", require: false
gem "tzinfo-data", platforms: %i[mingw mswin x64_mingw jruby]

# GraphQL
gem "graphql"
gem "graphql-pagination"

# Payment processing
gem "adyen-ruby-api-library"
gem "gocardless_pro", "~> 2.34"
gem "stripe"

# Analytics
gem "activejob-traceable"
gem "analytics-ruby", "~> 2.4.0", require: "segment/analytics"

# Logging
gem "lograge"
gem "logstash-event"

# HTTP and Multipart support
gem "multipart-post"
gem "mutex_m"

# Monitoring
gem "newrelic_rpm"
gem "opentelemetry-exporter-otlp"
gem "opentelemetry-instrumentation-all"
gem "opentelemetry-sdk"
gem "sentry-rails"
gem "sentry-ruby"
gem "sentry-sidekiq"

# Storage
gem "aws-sdk-s3", require: false
gem "google-cloud-storage", require: false

# Templating
gem "slim"
gem "slim-rails"

# Kafka
gem "karafka", "~> 2.4.17"
gem "karafka-web", "~> 0.10.4"

# Taxes
gem "valvat", require: false

# Data Export
gem "csv", "~> 3.0"

gem "lago-expression", github: "getlago/lago-expression", glob: "expression-ruby/lago-expression.gemspec", tag: "v0.1.3"

group :development, :test, :staging do
  gem "factory_bot_rails"
  gem "faker"
end

group :development, :test do
  gem "byebug"
  gem "clockwork-test"
  gem "debug", platforms: %i[mri mingw x64_mingw], require: false
  gem "dotenv"
  gem "fuubar"
  gem "i18n-tasks", git: "https://github.com/glebm/i18n-tasks.git"
  gem "rspec-rails"
  gem "simplecov", require: false
  gem "webmock"
  gem "rubocop-rails"
  gem "rubocop-graphql", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-thread_safety", require: false
  gem "awesome_print"
end

group :test do
  gem "database_cleaner-active_record"
  gem "guard-rspec", require: false
  gem "rspec-graphql_matchers"
  gem "shoulda-matchers"
  gem "karafka-testing"
end

group :development do
  gem "bullet"
  gem "coffee-rails"
  gem "graphiql-rails", git: "https://github.com/rmosolgo/graphiql-rails.git"

  gem "standard", require: false
  gem "annotate"

  gem "sass-rails"
  gem "uglifier"

  gem "ruby-lsp-rails", require: false
end
