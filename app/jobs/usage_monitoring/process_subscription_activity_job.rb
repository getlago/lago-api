# frozen_string_literal: true

module UsageMonitoring
  class ProcessSubscriptionActivityJob < ApplicationJob
    queue_as :default # where?

    def perform(subscription_activity_id)
      subscription_activity = SubscriptionActivity.find(subscription_activity_id)
      return unless subscription_activity

      ProcessSubscriptionActivityService.call(subscription_activity:)
    end
  end
end
