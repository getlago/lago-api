# frozen_string_literal: true

module Clock
  class SubscriptionsToBeTerminatedJob < ApplicationJob
    queue_as 'clock'

    def perform
      Subscription
        .joins(customer: :organization)
        .joins('left join webhooks on subscriptions.id = webhooks.object_id and '\
               "webhooks.webhook_type = 'subscription.termination_alert'")
        .active
        .where(
          'DATE(subscriptions.ending_at::timestamptz) IN (?)',
          [(Time.current + 45.days).to_date, (Time.current + 15.days).to_date],
        )
        .where('webhooks.id IS NULL OR webhooks.created_at::date != ?', Time.current.to_date)
        .find_each do |subscription|
          if subscription.customer.organization.webhook_endpoints.any?
            SendWebhookJob.perform_later('subscription.termination_alert', subscription)
          end
        end
    end
  end
end
