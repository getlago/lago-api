# frozen_string_literal: true

module Charges
  class UpdateChildrenJob < ApplicationJob
    queue_as :low_priority

    retry_on WithAdvisoryLock::FailedToAcquireLock,
      attempts: MAX_LOCK_RETRY_ATTEMPTS,
      wait: random_lock_retry_delay

    def perform(params:, old_parent_attrs:, old_parent_filters_attrs:, old_parent_applied_pricing_unit_attrs:)
      Charges::UpdateChildrenService.call!(
        params:,
        old_parent_attrs:,
        old_parent_filters_attrs:,
        old_parent_applied_pricing_unit_attrs:
      )
    end
  end
end
