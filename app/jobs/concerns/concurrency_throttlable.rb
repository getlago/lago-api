# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module ConcurrencyThrottlable
  extend ActiveSupport::Concern

  included do
    include Sidekiq::Throttled::Job

    # The limit of concurrent API calls defined in: config/initializers/throttling.rb
    sidekiq_throttle_as :concurrency_limit
  end
end
