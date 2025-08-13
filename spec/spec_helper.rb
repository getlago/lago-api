# frozen_string_literal: true

require "knapsack_pro"

# Custom Knapsack Pro config here
KnapsackPro::Adapters::RSpecAdapter.bind

# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"

# Explicitly require monkey patches after loading dependencies.
Dir[Rails.root.join("spec/support/monkey_patches/*.rb")].sort.each { |f| require f }

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

Dir[Rails.root.join("spec/support/**/*.rb")].sort.reject { |f| f.include?("_spec.rb") }.each { |f| require f }

begin
  ActiveRecord::Migration.check_all_pending!
rescue ActiveRecord::PendingMigrationError
  FileUtils.cd(Rails.root) { system("bin/rails db:migrate:primary RAILS_ENV=test") }
end

ENV["STRIPE_API_VERSION"] ||= "2020-08-27"

RSpec.configure do |config|
  config.include ActiveJob::TestHelper
  config.include FactoryBot::Syntax::Methods
  config.include GraphQLHelper, type: :graphql
  config.include AdminHelper, type: :request
  config.include ApiHelper, type: :request
  config.include ScenariosHelper
  config.include LicenseHelper
  config.include PdfHelper
  config.include StripeHelper
  config.include QueuesHelper
  config.include XMLHelper
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ActiveStorageValidations::Matchers
  config.include Karafka::Testing::RSpec::Helpers
  config.include GraphQL::Testing::Helpers.for(LagoApiSchema)

  # NOTE: these files make real API calls and should be excluded from build
  #       run them manually when needed
  config.exclude_pattern = "spec/integration/**/*_integration_spec.rb"

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [Rails.root.join("spec/fixtures").to_s]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, assign false
  config.use_transactional_fixtures = false

  config.infer_spec_type_from_file_location!
  config.define_derived_metadata(file_path: Regexp.new("/spec/graphql/")) do |metadata|
    metadata[:type] = :graphql
  end
  config.define_derived_metadata(file_path: Regexp.new("/spec/scenarios/")) do |metadata|
    metadata[:type] = :request
  end

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
  config.define_derived_metadata(file_path: Regexp.new("/spec/scenarios/")) do |metadata|
    metadata[:with_pdf_generation_stub] = true unless metadata.key?(:with_pdf_generation_stub)
  end

  # NOTE: Database cleaner config to turn off/on transactional mode
  config.before(:suite) do |example|
    # No need for `DatabaseCleaner[:active_record, db: EventsRecord].clean_with(:deletion)`
    # because both connections are using the same database.
    DatabaseCleaner[:active_record].clean_with(:deletion)

    # Clean Clickhouse database if any test is using it.
    if RSpec.world.all_examples.any? { |ex| ex.metadata[:clickhouse] }
      WebMock.disable_net_connect!(allow: ENV.fetch("LAGO_CLICKHOUSE_HOST", "clickhouse"))
      DatabaseCleaner[:active_record, db: Clickhouse::BaseRecord].clean_with(:deletion)
    end

    WebMock.disable_net_connect!
  end

  config.include_context "with Time travel enabled", :time_travel

  config.before(:each, :with_pdf_generation_stub) do |example|
    stub_pdf_generation
  end

  config.before do |example|
    metadata = example.metadata

    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow(Utils::ActivityLog).to receive(:produce).and_call_original

    if (clickhouse = metadata[:clickhouse])
      WebMock.disable_net_connect!(allow: ENV.fetch("LAGO_CLICKHOUSE_HOST", "clickhouse"))

      if clickhouse.is_a?(Hash) && clickhouse[:clean_before]
        DatabaseCleaner[:active_record, db: Clickhouse::BaseRecord].clean_with(:deletion)
      end
    end

    if metadata[:with_bullet] || metadata[:bullet]
      Bullet.enable = true
      bullet_metadata = example.metadata[:bullet] || {}
      Bullet.n_plus_one_query_enable = bullet_metadata.fetch(:n_plus_one_query, true)
      Bullet.unused_eager_loading_enable = bullet_metadata.fetch(:unused_eager_loading, true)
      Bullet.start_request
    end

    if metadata[:cache]
      Rails.cache = if example.metadata[:cache].to_sym == :memory
        ActiveSupport::Cache.lookup_store(:memory_store)
      elsif metadata[:cache].to_sym == :null
        ActiveSupport::Cache.lookup_store(:null_store)
      elsif metadata[:cache].to_sym == :redis
        ActiveSupport::Cache.lookup_store(:redis_cache_store)
      else
        raise "Unknown cache store: #{example.metadata[:cache]}"
      end
    end
  end

  config.after do |example|
    if example.metadata[:with_bullet] || example.metadata[:bullet]
      Bullet.perform_out_of_channel_notifications if Bullet.notification?
      Bullet.end_request
    end
    Bullet.enable = false
  end

  config.around do |example|
    # Important to set the strategy in this block as otherwise the cleaning will always use the transaction strategy
    strategy = if example.metadata[:transaction] == false
      :deletion
    else
      :transaction
    end
    DatabaseCleaner.strategy = strategy

    # We need to set the strategy for the `events` connection as well to properly rollback changes done using the `events` connection.
    # DO NOT CHANGE `:db` to `:events` as it will not work properly with `:transaction` strategy.
    DatabaseCleaner[:active_record, db: EventsRecord].strategy = if strategy == :transaction
      :transaction
    else
      # If the `deletion` strategy is used for the default connection, we don't need to set it for the `events` connection as they are using the same database.
      DatabaseCleaner::NullStrategy.new
    end

    # Clickhouse doesn't support transaction so we default to null strategy to skip cleanup when not needed.
    DatabaseCleaner[:active_record, db: Clickhouse::BaseRecord].strategy = DatabaseCleaner::NullStrategy.new

    DatabaseCleaner.cleaning do
      example.run
    end
  end

  config.around do |example|
    if example.metadata[:premium]
      lago_premium!(&example)
    else
      example.run
    end
  end
end
