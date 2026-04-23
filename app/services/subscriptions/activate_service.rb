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
      return result if subscription.active?
      return result if subscription.gated?

      if subscription.pending_rules?
        subscription.mark_as_incomplete!
      else
        subscription.mark_as_active!(timestamp)
      end

      EmitFixedChargeEventsService.call!(
        subscriptions: [subscription],
        timestamp: subscription.started_at + 1.second
      )

      after_commit do
        bill_subscription

        if gated?
          SendWebhookJob.perform_later("subscription.incomplete", subscription)
          Utils::ActivityLog.produce(subscription, "subscription.incomplete")
        else
          SendWebhookJob.perform_later("subscription.started", subscription)
          Utils::ActivityLog.produce(subscription, "subscription.started")

          if subscription.should_sync_hubspot_subscription?
            Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
          end
        end
      end

      result.subscription = subscription
      result
    end

    private

    attr_reader :subscription, :timestamp

    def gated?
      subscription.incomplete?
    end

    def payment_gated?
      gated? && subscription.activation_rules.payment.pending.any?
    end

    def bill_subscription
      return if gated? && !payment_gated?

      if subscription.plan.pay_in_advance? && !subscription.in_trial_period?
        BillSubscriptionJob.perform_later(
          [subscription],
          timestamp.to_i,
          invoicing_reason: :subscription_starting,
          skip_charges: gated?
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
