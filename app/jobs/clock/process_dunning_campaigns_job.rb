# frozen_string_literal: true

module Clock
  class ProcessDunningCampaignsJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'
    limits_concurrency to: 1, key: 'process_dunning_campaign', duration: 1.hour

    def perform
      return unless License.premium?

      DunningCampaigns::BulkProcessJob.perform_later
    end
  end
end
