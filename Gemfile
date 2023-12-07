# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.2.2'

# Core
gem 'aasm'
gem 'activejob-uniqueness', require: 'active_job/uniqueness/sidekiq_patch'
gem 'bootsnap', require: false
gem 'clockwork', require: false
gem 'puma', '~> 5.6'
gem 'rails', '~> 7.0.8'
gem 'sidekiq'

# Security
gem 'bcrypt'
gem 'googleauth', require: false
gem 'jwt'
gem 'oauth2'
gem 'rack-cors'

# Database
gem 'clickhouse-activerecord', git: 'https://github.com/getlago/clickhouse-activerecord.git'
gem 'discard', '~> 1.2'
gem 'kaminari-activerecord'
gem 'paper_trail'
gem 'pg'
gem 'ransack', '~> 4.0.0'
gem 'scenic'
gem 'with_advisory_lock'

# Currencies, Countries, Timezones...
gem 'countries'
gem 'money-rails'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]

# GraphQL
gem 'graphql'
gem 'graphql-pagination'

# Payment processing
gem 'adyen-ruby-api-library'
gem 'gocardless_pro', '~> 2.34'
gem 'stripe'

# Analytics
gem 'activejob-traceable'
gem 'analytics-ruby', '~> 2.4.0', require: 'segment/analytics'

# Logging
gem 'lograge'
gem 'lograge-sql'
gem 'logstash-event'

# Multipart support
gem 'multipart-post'

# Monitoring
gem 'newrelic_rpm'
gem 'sentry-rails', '~> 5.12.0'
gem 'sentry-ruby', '~> 5.12.0'
gem 'sentry-sidekiq', '~> 5.12.0'

# Storage
gem 'aws-sdk-s3', require: false
gem 'google-cloud-storage', require: false

# Templating
gem 'slim'
gem 'slim-rails'

# Kafka
gem 'karafka'

# Taxes
gem 'valvat', require: false

group :development, :test, :staging do
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'timecop'
end

group :development, :test do
  gem 'byebug'
  gem 'clockwork-test'
  gem 'debug', platforms: %i[mri mingw x64_mingw]
  gem 'dotenv'
  gem 'i18n-tasks', git: 'https://github.com/glebm/i18n-tasks.git'
  gem 'rspec-rails'
  gem 'simplecov', require: false
  gem 'webmock'
end

group :test do
  gem 'database_cleaner-active_record'
  gem 'rspec-graphql_matchers'
  gem 'shoulda-matchers'
end

group :development do
  gem 'coffee-rails'
  gem 'graphiql-rails', git: 'https://github.com/rmosolgo/graphiql-rails.git'
  gem 'sass-rails'
  gem 'uglifier'
end
