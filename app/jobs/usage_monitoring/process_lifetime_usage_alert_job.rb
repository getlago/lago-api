# frozen_string_literal: true

module UsageMonitoring
  class ProcessLifetimeUsageAlertJob < ApplicationJob
    unique :until_executed, on_conflict: :log
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_ALERTS"])
        :alerts
      else
        :default
      end
    end

    def perform(alert:, subscription:)
      ProcessLifetimeUsageAlertService.call!(alert:, subscription:)
    end

    private

    def lock_key_arguments
      [arguments.first[:alert]]
    end
  end
end
