# frozen_string_literal: true

module Clock
  class SubscriptionsToBeTerminatedJob < ApplicationJob
    queue_as 'clock'

    def perform
      Subscription
        .joins(customer: :organization)
        .joins('left join webhooks on subscriptions.id = webhooks.object_id and '\
               "webhooks.webhook_type = 'subscription.reaching_termination'")
        .active
        .where("DATE(#{Subscription.ending_at_in_timezone_sql}) = ?", (Time.current + 15.days).to_date)
        .where('webhooks.id IS NULL')
        .find_each do |subscription|
          if subscription.customer.organization.webhook_endpoints.any?
            SendWebhookJob.perform_later('subscription.reaching_termination', subscription)
          end
        end
    end
  end
end
