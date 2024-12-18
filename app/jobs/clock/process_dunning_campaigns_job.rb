# frozen_string_literal: true

module Clock
  class ProcessDunningCampaignsJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_CLOCK'])
        :clock_worker
      else
        :clock
      end
    end

    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      DunningCampaigns::BulkProcessJob.perform_later
    end
  end
end
