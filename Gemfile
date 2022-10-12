# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.0.1'

gem 'activejob-traceable'
gem 'analytics-ruby', '~> 2.4.0', require: 'segment/analytics'
gem 'bcrypt'
gem 'bootsnap', require: false
gem 'clockwork', require: false
gem 'countries'
gem 'graphql'
gem 'graphql-pagination'
gem 'jwt'
gem 'kaminari-activerecord'
gem 'money-rails'
gem 'pg'
gem 'puma', '~> 5.6'
gem 'rack-cors'
gem 'rails', '~> 7.0.3.1'
gem 'sidekiq'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]
gem 'with_advisory_lock'

# Payment processing
gem 'stripe'

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
