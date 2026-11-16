# frozen_string_literal: true

module ConcurrencyThrottlable
  extend ActiveSupport::Concern

  NEXT_WINDOW_MAX_JITTER = 30 # seconds

  included do
    include Sidekiq::Throttled::Job

    # The limit of concurrent API calls defined in: config/initializers/throttling.rb
    sidekiq_throttle_as :concurrency_limit

    # NOTE: A rate limited job is waiting for its turn, not failing. It is retried once the window
    # has passed, with jitter to spread the backlog, and without an attempt cap.
    rescue_from(BaseService::NextWindowThrottlingError) do |error|
      retry_job(wait: error.retry_after + rand(0..NEXT_WINDOW_MAX_JITTER).seconds, error:)
    end
  end
end
