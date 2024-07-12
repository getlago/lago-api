# frozen_string_literal: true

require 'webmock/rspec'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # NOTE: Database cleaner config to turn off/on transactional mode
  config.before(:suite) do
    DatabaseCleaner.clean_with(:deletion)
  end

  config.before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  config.before do
    DatabaseCleaner.strategy = :transaction
  end

  # Custom metadata
  config.before do |example|
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

  config.before(:each, transaction: false) do
    DatabaseCleaner.strategy = :deletion
  end

  config.around do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  config.before(:each, clickhouse: true) do
    DatabaseCleaner.strategy = :deletion
    WebMock.disable_net_connect!(allow: ENV.fetch('LAGO_CLICKHOUSE_HOST', 'clickhouse'))
  end
end
