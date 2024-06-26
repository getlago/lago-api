# frozen_string_literal: true

# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV['RAILS_ENV'] = 'test'
require_relative '../config/environment'

require 'spec_helper'
require 'simplecov'

def pp(*args)
  # Uncomment the following line if you can't find where you left a `pp` call
  # ap caller.first
  args.each do |arg|
    ap arg, {sort_vars: false, sort_keys: false, indent: -2}
  end
end

DatabaseCleaner.allow_remote_database_url = true

SimpleCov.start do
  enable_coverage :branch

  add_filter %r{^/config/}
  add_filter %r{^/db/}
  add_filter '/spec/'

  add_group 'Controllers', 'app/controllers'
  add_group 'Models', 'app/models'
  add_group 'Jobs', %w[app/jobs app/workers]
  add_group 'Services', 'app/services'
  add_group 'GraphQL', 'app/graphql'
end

# Prevent database truncation if the environment is production
abort('The Rails environment is running in production mode!') if Rails.env.production?
require 'rspec/rails'
require 'paper_trail/frameworks/rspec'
require 'sidekiq/testing'
Sidekiq::Testing.fake!
ActiveJob::Uniqueness.test_mode!

Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts e.to_s.strip
  exit 1
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include GraphQLHelper, type: :graphql
  config.include AdminHelper, type: :request
  config.include ApiHelper, type: :request
  config.include ScenariosHelper
  config.include LicenseHelper
  config.include PdfHelper
  config.include ActiveSupport::Testing::TimeHelpers

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [Rails.root.join('spec/fixtures').to_s]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = false

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # You can disable this behaviour by removing the line below, and instead
  # explicitly tag your specs with their type, e.g.:
  #
  #     RSpec.describe UsersController, type: :controller do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://relishapp.com/rspec/rspec-rails/docs
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")
end
