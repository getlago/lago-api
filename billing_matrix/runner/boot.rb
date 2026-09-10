# frozen_string_literal: true

require_relative "errors"

module BillingMatrix
  APP_ROOT = File.expand_path("../..", __dir__)

  # Deliberately a class instance variable: this guards a once-per-process side effect —
  # requiring the Rails environment — in a single-threaded CLI. A thread-safe alternative
  # would only add a mutex around something that must happen before any thread exists.
  # rubocop:disable ThreadSafety/ClassInstanceVariable
  def self.boot!
    return if @booted

    ENV["RAILS_ENV"] = "test"
    require File.join(APP_ROOT, "config/environment")
    abort_unless_test_environment!

    Dir[File.join(APP_ROOT, "spec/support/monkey_patches/*.rb")].sort.each { |f| require f }

    require "webmock"
    WebMock.enable!
    WebMock.disable_net_connect!

    require "sidekiq/testing"
    Sidekiq::Testing.fake!

    require "factory_bot"
    # factory_bot_rails is in the Gemfile's test group, so its railtie already ran
    # find_definitions during config/environment; a second call raises DuplicateDefinitionError.
    FactoryBot.reload

    require "database_cleaner/active_record"
    DatabaseCleaner.allow_remote_database_url = true
    DatabaseCleaner[:active_record].clean_with(:deletion)

    ActiveJob::Uniqueness.test_mode!

    @booted = true
    nil
  end
  # rubocop:enable ThreadSafety/ClassInstanceVariable

  def self.abort_unless_test_environment!
    unless Rails.env.test?
      abort("billing_matrix: refusing to run — Rails.env is #{Rails.env.inspect}, expected \"test\"")
    end

    database = ActiveRecord::Base.connection_db_config.database
    unless database.to_s.end_with?("_test")
      abort("billing_matrix: refusing to run — database #{database.inspect} does not end in \"_test\" " \
            "(this runner deletes every row; set DATABASE_TEST_URL to a *_test database)")
    end
  end
  private_class_method :abort_unless_test_environment!
end
