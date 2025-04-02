# frozen_string_literal: true

module Clock
  class ProcessDunningCampaignsJob < ApplicationJob
    if ENV["SENTRY_DSN"].present? && ENV["SENTRY_ENABLE_CRONS"].present?
      include SentryCronConcern
    end

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
        :clock_worker
      else
        :clock
      end
    end

    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      Organization.with_auto_dunning_support.find_each do |organization|
        DunningCampaigns::OrganizationProcessJob.perform_later(organization)
      end
    end
  end
end
