# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.0.1'

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
gem 'rails', '~> 7.0.2'
gem 'sidekiq'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]
gem 'with_advisory_lock'

group :development, :test do
  gem 'byebug'
  gem 'clockwork-test'
  gem 'debug', platforms: %i[mri mingw x64_mingw]
  gem 'dotenv'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'rspec-rails'
  gem 'simplecov', require: false
end

group :development do
  gem 'coffee-rails'
  gem 'graphiql-rails', git: 'https://github.com/rmosolgo/graphiql-rails.git'
  gem 'sass-rails'
  gem 'uglifier'
end
