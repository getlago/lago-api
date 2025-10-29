# frozen_string_literal: true

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.4.7"

# Core
gem "aasm"
gem "activejob-uniqueness", require: "active_job/uniqueness/sidekiq_patch"
gem "active_storage_validations"
gem "bootsnap", require: false
gem "clockwork", require: false
gem "parallel"
gem "puma", "~> 6.5"
gem "rails", "~> 8.0"
gem "redis"
gem "sidekiq"
group :'sidekiq-pro', optional: true do
  source "https://gems.contribsys.com/" do
    gem "sidekiq-pro"
  end
end
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
gem "clickhouse-activerecord", "~> 1.3.0"
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
gem "analytics-ruby", "~> 2.4.0", require: "segment/analytics"

# SSE
gem "event_stream_parser"

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
gem "yabeda"
gem "yabeda-rails", github: "getlago/yabeda-rails", glob: "yabeda-rails.gemspec", ref: "6dd4d74"
gem "yabeda-puma-plugin"
gem "yabeda-prometheus"

gem "stackprof", require: false, platforms: [:ruby, :mri]
gem "sentry-rails"
gem "sentry-ruby"
gem "sentry-sidekiq"

# Storage
gem "aws-sdk-s3", require: false
gem "google-cloud-storage", require: false

# Templating
gem "slim"
gem "slim-rails"
gem "addressing"

# Kafka
gem "karafka", "~> 2.5.0"
gem "karafka-web", "~> 0.11.3"

# Taxes
gem "valvat"

# Data Export
gem "csv", "~> 3.0"
gem "ostruct"

gem "lago-expression", github: "getlago/lago-expression", glob: "expression-ruby/lago-expression.gemspec", tag: "v0.1.5"

group :development, :test, :staging do
  gem "factory_bot_rails"
  gem "faker"
end

group :development, :test do
  gem "bullet"
  gem "clockwork-test"
  gem "debug", platforms: %i[mri mingw x64_mingw], require: false
  gem "dotenv"
  gem "fuubar"
  gem "rspec-rails"
  gem "simplecov", require: false
  gem "webmock"
  gem "awesome_print"
  gem "pry-byebug"
  gem "knapsack_pro", "~> 8.1"
  gem "parallel_tests", "~> 5.3"

  gem "database_cleaner-active_record"
  gem "rspec-graphql_matchers"
  gem "shoulda-matchers"

  gem "i18n-tasks", git: "https://github.com/glebm/i18n-tasks.git", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-graphql", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-thread_safety", require: false
end

group :test do
  gem "guard-rspec", require: false
  gem "karafka-testing"

  # HTML testing (invoice rendering)
  gem "rspec-snapshot", "~> 2.0"
  gem "htmlbeautifier", "~> 1.4"
end

group :development do
  gem "coffee-rails"
  gem "graphiql-rails", git: "https://github.com/rmosolgo/graphiql-rails.git"
  gem "httplog"

  gem "standard", require: false
  gem "annotaterb"

  gem "sass-rails"
  gem "uglifier"

  gem "ruby-lsp-rails", require: false
end
