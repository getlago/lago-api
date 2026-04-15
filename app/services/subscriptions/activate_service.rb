# frozen_string_literal: true

module Subscriptions
  class ActivateService < BaseService
    Result = BaseResult[:subscription]

    def initialize(subscription:, timestamp: Time.current)
      @subscription = subscription
      @timestamp = timestamp
      super
    end

    def call
      result.subscription = subscription
      return result if subscription.active?

      subscription.mark_as_active!(timestamp)

      EmitFixedChargeEventsService.call!(
        subscriptions: [subscription],
        timestamp: subscription.started_at + 1.second
      )

      bill_subscription

      SendWebhookJob.perform_later("subscription.started", subscription)
      Utils::ActivityLog.produce(subscription, "subscription.started")

      if subscription.should_sync_hubspot_subscription?
        Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
      end

      result
    end

    private

    attr_reader :subscription, :timestamp

    def bill_subscription
      if subscription.plan.pay_in_advance? && !subscription.in_trial_period?
        BillSubscriptionJob.perform_later(
          [subscription],
          timestamp.to_i,
          invoicing_reason: :subscription_starting,
          skip_charges: true
        )
      elsif subscription.fixed_charges.pay_in_advance.any?
        Invoices::CreatePayInAdvanceFixedChargesJob.perform_later(
          subscription,
          subscription.started_at + 1.second
        )
      end
    end
  end
end
