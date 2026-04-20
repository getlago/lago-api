# frozen_string_literal: true

module Subscriptions
  class GatedActivationService < BaseService
    Result = BaseResult[:subscription]

    def initialize(subscription:)
      @subscription = subscription
      super
    end

    def call
      return result unless subscription.pending_rules?
      return result if subscription.active? || subscription.incomplete?

      subscription.mark_as_incomplete!

      EmitFixedChargeEventsService.call!(
        subscriptions: [subscription],
        timestamp: subscription.started_at + 1.second
      )

      after_commit do
        bill_subscription

        SendWebhookJob.perform_later("subscription.incomplete", subscription)
        Utils::ActivityLog.produce(subscription, "subscription.incomplete")
      end

      result.subscription = subscription
      result
    end

    private

    attr_reader :subscription

    def bill_subscription
      if subscription.plan.pay_in_advance? && !subscription.in_trial_period?
        BillSubscriptionJob.perform_later(
          [subscription],
          Time.current.to_i,
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
