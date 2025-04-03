# frozen_string_literal: true

require "knapsack_pro"

# Custom Knapsack Pro config here
KnapsackPro::Adapters::RSpecAdapter.bind

# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"

# Allow remote debugging when RUBY_DEBUG_PORT is set
if ENV["RUBY_DEBUG_PORT"]
  require "debug/open_nonstop"
else
  require "debug"
end

require "webmock/rspec"
require "simplecov"
require "money-rails/test_helpers"
require "active_storage_validations/matchers"
require "karafka/testing/rspec/helpers"

DatabaseCleaner.allow_remote_database_url = true

SimpleCov.start do
  enable_coverage :branch

  add_filter %r{^/config/}
  add_filter %r{^/db/}
  add_filter "/spec/"

  add_group "Controllers", "app/controllers"
  add_group "Models", "app/models"
  add_group "Jobs", %w[app/jobs app/workers]
  add_group "Services", "app/services"
  add_group "GraphQL", "app/graphql"
end

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "paper_trail/frameworks/rspec"
require "sidekiq/testing"
Sidekiq::Testing.fake!
ActiveJob::Uniqueness.test_mode!

Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

# Checks for pending migrations
begin
  ActiveRecord::Migration.check_all_pending!
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
  config.include QueuesHelper
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ActiveStorageValidations::Matchers
  config.include Karafka::Testing::RSpec::Helpers

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [Rails.root.join("spec/fixtures").to_s]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, assign false
  config.use_transactional_fixtures = false

  config.infer_spec_type_from_file_location!

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.example_status_persistence_file_path = "tmp/rspec_examples.txt"
  config.filter_run_when_matching :focus

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  config.define_derived_metadata do |meta|
    unless meta.key?(:aggregate_failures)
      meta[:aggregate_failures] = true
    end
  end

  # NOTE: Database cleaner config to turn off/on transactional mode
  config.before(:suite) do
    DatabaseCleaner.clean_with(:deletion)
  end

  config.include_context "with Time travel enabled", :time_travel

  config.before do |example|
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    DatabaseCleaner.strategy = :transaction

    if example.metadata[:transaction] == false
      DatabaseCleaner.strategy = :deletion
    end

    if example.metadata[:scenarios]
      stub_pdf_generation
    end

    if example.metadata[:clickhouse]
      DatabaseCleaner.strategy = :deletion
      WebMock.disable_net_connect!(allow: ENV.fetch("LAGO_CLICKHOUSE_HOST", "clickhouse"))
    end

    if example.metadata[:cache]
      Rails.cache = if example.metadata[:cache].to_sym == :memory
        ActiveSupport::Cache.lookup_store(:memory_store)
      elsif example.metadata[:cache].to_sym == :null
        ActiveSupport::Cache.lookup_store(:null_store)
      elsif example.metadata[:cache].to_sym == :redis
        ActiveSupport::Cache.lookup_store(:redis_cache_store)
      else
        raise "Unknown cache store: #{example.metadata[:cache]}"
      end
    end
  end

  config.around do |example|
    if example.metadata[:bypass_cleaner]
      example.run
    else
      DatabaseCleaner.cleaning do
        example.run
      end
    end
  end
end
