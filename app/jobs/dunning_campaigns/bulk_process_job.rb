# frozen_string_literal: true

module DunningCampaigns
  class BulkProcessJob < ApplicationJob
    queue_as :low_priority

    unique :until_executed, on_conflict: :log, lock_ttl: 2.hours

    def perform
      return unless License.premium?

      DunningCampaigns::BulkProcessService.call.raise_if_error!
    rescue
      # The lock is only released in `after_perform`, which is skipped when the job raises.
      # Without this, a failed run would make the clock drop the next runs until `lock_ttl`.
      lock_strategy.unlock(resource: lock_key)
      raise
    end
  end
end
