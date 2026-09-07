# frozen_string_literal: true

require_relative "boot"

BillingMatrix.boot!

require "action_dispatch/testing/integration"
require "active_job/test_helper"
require "active_support/testing/time_helpers"
require_relative "../../spec/support/api_helper"
require_relative "../../spec/support/queues_helper"
require_relative "../../spec/support/scenarios_helper"
require_relative "../../spec/support/pdf_helper"
require_relative "../../spec/support/license_helper"

module BillingMatrix
  class Context
    # Terminal no-ops for the before_setup/after_teardown chains that Minitest::Test
    # normally terminates; must sit below every other include.
    module Lifecycle
      def before_setup; end
      def after_teardown; end
    end

    include Lifecycle
    include FactoryBot::Syntax::Methods
    include ActiveSupport::Testing::TimeHelpers
    include ActiveJob::TestHelper
    include ActionDispatch::Integration::Runner
    include WebMock::API
    include ApiHelper
    include QueuesHelper
    include ScenariosHelper
    include PdfHelper
    include LicenseHelper

    SCENARIO_READERS = %i[
      organization customer plan subscription billable_metric billing_entity tax coupon wallet
    ].freeze

    attr_accessor(*SCENARIO_READERS)

    # What a step produced that is not reachable from the database afterwards: a preview is
    # never persisted, and a rejected call leaves only an HTTP status. Timeline writes these,
    # Observe reads them. They are declared here rather than left to Timeline's singleton
    # stash so that Observe never has to fall back to "whatever the last API call returned".
    STASHED = %i[preview error].freeze

    attr_accessor(*STASHED)

    # `enter` runs inside the begin, not before it: it mutates global state — the premium
    # flag, WebMock stubs, the time offset — so an `enter` that raises halfway must still
    # reach `leave`, or it leaks all of that into the next row.
    def self.isolate
      ctx = new
      begin
        ctx.enter
        yield ctx
      ensure
        ctx.leave
      end
    end

    def initialize
      super()
      (SCENARIO_READERS + STASHED).each { |name| instance_variable_set(:"@#{name}", nil) }
    end

    def app
      Rails.application
    end

    def travel_to_and_run(iso8601_string, &block)
      travel_to(DateTime.iso8601(iso8601_string), &block)
    end

    def mock_vies_check!(_vat_number)
      raise Unsupported, "mock_vies_check! relies on rspec-mocks (instance_double/allow) and is not available in the matrix runner"
    end

    def enter
      self.class.clean_database!
      before_setup
      reset!
      Sidekiq::Worker.clear_all
      WebMock.reset!
      stub_pdf_generation
      License.instance_variable_set(:@premium, true)
      travel_back
    end

    def leave
      run_all_even_if_one_fails(
        -> { travel_back },
        -> { after_teardown },
        -> { clear_enqueued_jobs },
        -> { clear_performed_jobs },
        -> { Sidekiq::Worker.clear_all },
        -> { WebMock.reset! },
        -> { License.instance_variable_set(:@premium, false) },
        -> { self.class.clean_database! }
      )
    end

    def self.clean_database!
      cleaner = DatabaseCleaner[:active_record]
      cleaner.strategy = :deletion
      cleaner.clean
    end

    private

    def run_all_even_if_one_fails(*steps)
      first_error = nil
      steps.each do |step|
        begin
          step.call
        rescue Exception => e # rubocop:disable Lint/RescueException
          first_error ||= e
        end
      end
      raise first_error if first_error
    end
  end
end
