# frozen_string_literal: true

module Clock
  class ProcessDunningCampaignsJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'

    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      Dunning::ProcessCampaignsJob.perform_later
    end
  end
end
