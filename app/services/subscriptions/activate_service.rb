# frozen_string_literal: true

module Subscriptions
  class ActivateService < BaseService
    Result = BaseResult[:subscription]

    def initialize(subscription:, timestamp: Time.current, during_creation: false)
      @subscription = subscription
      @timestamp = timestamp
      @during_creation = during_creation
      super
    end

    def call
      return result if subscription.active?
      return result if subscription.gated?

      if subscription.pending?
        activate_from_pending
      elsif subscription.incomplete?
        activate_from_incomplete
      end

      result.subscription = subscription
      result
    end

    private

    attr_reader :subscription, :timestamp, :during_creation

    def activate_from_pending
      ActivationRules::EvaluateService.call!(subscription:)

      if subscription.pending_rules?
        gate_subscription
      else
        activate_with_side_effects
      end
    end

    def activate_from_incomplete
      return if subscription.activation_rules.rejected.exists?

      subscription.mark_as_active!(timestamp)

      after_commit do
        bill_subscription if subscription.activation_rules.payment.none?
        notify_started
      end
    end

    def gate_subscription
      subscription.mark_as_incomplete!

      EmitFixedChargeEventsService.call!(
        subscriptions: [subscription],
        timestamp: subscription.started_at + 1.second
      )

      after_commit do
        bill_subscription(skip_charges: true) if subscription.payment_gated?

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
        bill_subscription(skip_charges: true)
        notify_started
      end
    end

    def notify_started
      SendWebhookJob.perform_later("subscription.started", subscription)
      Utils::ActivityLog.produce(subscription, "subscription.started")

      # Skip Hubspot UpdateJob when activating during subscription creation —
      # CreateService fires Hubspot::CreateJob after this, which captures the
      # active state and avoids a redundant Update that would race with Create.
      return if during_creation

      if subscription.should_sync_hubspot_subscription?
        Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
      end
    end

    def bill_subscription(skip_charges: false)
      if subscription.plan.pay_in_advance? && !subscription.in_trial_period?
        BillSubscriptionJob.perform_later(
          [subscription],
          timestamp.to_i,
          invoicing_reason: :subscription_starting,
          skip_charges:
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
