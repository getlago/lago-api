# frozen_string_literal: true

module Subscriptions
  class ActivateService < BaseService
    def initialize(timestamp:)
      @timestamp = timestamp

      super(nil)
    end

    def activate_all_pending
      Subscription
        .joins(customer: :billing_entity)
        .pending
        .where(previous_subscription: nil)
        .where(
          "DATE(subscriptions.subscription_at#{at_time_zone}) <= " \
          "DATE(?#{at_time_zone})",
          Time.zone.at(timestamp)
        )
        .find_each do |subscription|
          subscription.mark_as_active!(Time.zone.at(timestamp))

          EmitFixedChargeEventsService.call!(
            subscriptions: [subscription],
            timestamp: subscription.started_at
          )

          if subscription.should_sync_hubspot_subscription?
            Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
          end

          SendWebhookJob.perform_later("subscription.started", subscription)
          Utils::ActivityLog.produce(subscription, "subscription.started")

          if subscription.plan.pay_in_advance? && !subscription.in_trial_period?
            BillSubscriptionJob.perform_later([subscription], timestamp, invoicing_reason: :subscription_starting)
          end
        end
    end

    private

    attr_reader :timestamp
  end
end
