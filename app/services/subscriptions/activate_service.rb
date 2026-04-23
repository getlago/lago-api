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

      if subscription.pending?
        activate_from_pending
      elsif subscription.incomplete?
        activate_from_incomplete
      else
        raise "Unknown activation flow for subscription status: #{subscription.status}"
      end

      result.subscription = subscription
      result
    end

    private

    attr_reader :subscription, :timestamp

    def activate_from_pending
      ActivationRules::EvaluateService.call!(subscription:)

      if subscription.pending_rules?
        gate_subscription
      else
        activate_with_side_effects
      end
    end

    def activate_from_incomplete
      subscription.mark_as_active!(timestamp)

      after_commit do
        bill_subscription if subscription.activation_rules.payment.none?

        SendWebhookJob.perform_later("subscription.started", subscription)
        Utils::ActivityLog.produce(subscription, "subscription.started")

        if subscription.should_sync_hubspot_subscription?
          Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
        end
      end
    end

    def gate_subscription
      subscription.mark_as_incomplete!

      EmitFixedChargeEventsService.call!(
        subscriptions: [subscription],
        timestamp: subscription.started_at + 1.second
      )

      after_commit do
        bill_subscription if subscription.payment_gated?

        SendWebhookJob.perform_later("subscription.incomplete", subscription)
        Utils::ActivityLog.produce(subscription, "subscription.incomplete")
      end
    end

    def activate_with_side_effects
      subscription.mark_as_active!(timestamp)

      EmitFixedChargeEventsService.call!(
        subscriptions: [subscription],
        timestamp: subscription.started_at + 1.second
      )

      after_commit do
        bill_subscription

        SendWebhookJob.perform_later("subscription.started", subscription)
        Utils::ActivityLog.produce(subscription, "subscription.started")

        if subscription.should_sync_hubspot_subscription?
          Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
        end
      end
    end

    def bill_subscription
      if subscription.plan.pay_in_advance? && !subscription.in_trial_period?
        BillSubscriptionJob.perform_later(
          [subscription],
          timestamp.to_i,
          invoicing_reason: :subscription_starting,
          skip_charges: subscription.incomplete?
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
