# frozen_string_literal: true

module DunningCampaigns
  class BulkProcessJob < ApplicationJob
    queue_as :low_priority

    unique :until_executed, on_conflict: :log, lock_ttl: 2.hours

    def perform
      return unless License.premium?

      DunningCampaigns::BulkProcessService.call.raise_if_error!
    end
  end
end
