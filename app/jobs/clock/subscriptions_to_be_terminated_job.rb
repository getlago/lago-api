# frozen_string_literal: true

module Clock
  class SubscriptionsToBeTerminatedJob < ClockJob
    def perform
      Subscription
        .joins(customer: :organization)
        .joins("left join webhooks on subscriptions.id = webhooks.object_id and " \
               "webhooks.webhook_type = 'subscription.termination_alert'")
        .active
        .where(
          "DATE(subscriptions.ending_at::timestamptz) IN (?)",
          sent_at_dates
        )
        .where("webhooks.id IS NULL OR webhooks.created_at::date != ?", Time.current.to_date)
        .distinct
        .find_each do |subscription|
          SendWebhookJob.perform_later("subscription.termination_alert", subscription)
        end
    end

    private

    def sent_at_dates
      # NOTE: The alert will be sent 15 and 45 days before the subscription is terminated by default.
      #       You can override the default by setting below env var.
      #       E.g. LAGO_SUBSCRIPTION_TERMINATION_ALERT_SENT_AT_DAYS=1,15,45 will cause it
      #       to be sent at 1, 15, 45 days before subscription terminates, respectively.
      sent_at_days_config = ENV.fetch("LAGO_SUBSCRIPTION_TERMINATION_ALERT_SENT_AT_DAYS", "15,45")
      sent_at_days_config.split(",").map { |day_string| Time.current + day_string.to_i.days }.map(&:to_date)
    end
  end
end
