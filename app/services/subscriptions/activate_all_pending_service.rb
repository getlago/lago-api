# frozen_string_literal: true

module Subscriptions
  class ActivateAllPendingService < BaseService
    Result = BaseResult

    def initialize(timestamp:)
      @timestamp = timestamp

      super
    end

    def call
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
          fixed_charge_timestamp = subscription.started_at + 1.second

          EmitFixedChargeEventsService.call!(
            subscriptions: [subscription],
            timestamp: fixed_charge_timestamp
          )

          if subscription.should_sync_hubspot_subscription?
            Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
          end

          SendWebhookJob.perform_later("subscription.started", subscription)
          Utils::ActivityLog.produce(subscription, "subscription.started")

          if subscription.plan.pay_in_advance? && !subscription.in_trial_period?
            BillSubscriptionJob.perform_later([subscription], timestamp, invoicing_reason: :subscription_starting)
          elsif subscription.fixed_charges.pay_in_advance.any?
            Invoices::CreatePayInAdvanceFixedChargesJob.perform_later(subscription, fixed_charge_timestamp)
          end
        end

      result
    end

    private

    attr_reader :timestamp
  end
end
