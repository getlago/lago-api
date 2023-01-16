# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.1.3'

# Core
gem 'activejob-uniqueness', require: 'active_job/uniqueness/sidekiq_patch'
gem 'bootsnap', require: false
gem 'clockwork', require: false
gem 'puma', '~> 5.6'
gem 'rails', '~> 7.0.4'
gem 'sidekiq'

# Security
gem 'bcrypt'
gem 'jwt'
gem 'oauth2'
gem 'rack-cors'

# Database
gem 'kaminari-activerecord'
gem 'pg'
gem 'ransack'
gem 'with_advisory_lock'

# Currencies, Countries, Timezones...
gem 'countries'
gem 'money-rails'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]

# GraphQL
gem 'graphql'
gem 'graphql-pagination'

# Payment processing
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
gem 'sentry-rails'
gem 'sentry-ruby'
gem 'sentry-sidekiq'

# Storage
gem 'aws-sdk-s3', require: false
gem 'google-cloud-storage', require: false

# PDF Templating
gem 'slim'

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
  gem 'rspec-rails'
  gem 'simplecov', require: false
  gem 'webmock'
end

group :development do
  gem 'coffee-rails'
  gem 'graphiql-rails', git: 'https://github.com/rmosolgo/graphiql-rails.git'
  gem 'sass-rails'
  gem 'uglifier'
end
