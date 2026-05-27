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
      subscription.mark_as_incomplete!(timestamp)

      emit_fixed_charge_events

      after_commit do
        bill_subscription(skip_charges: true) if subscription.payment_gated?

        SendWebhookJob.perform_later("subscription.incomplete", subscription)
        Utils::ActivityLog.produce(subscription, "subscription.incomplete")
      end
    end

    def activate_with_side_effects
      if upgrade?
        activate_for_upgrade
      else
        activate_standalone
      end
    end

    def upgrade?
      return false unless subscription.previous_subscription
      return false if subscription.plan.id == subscription.previous_subscription.plan.id

      subscription.plan.yearly_amount_cents >= subscription.previous_subscription.plan.yearly_amount_cents
    end

    def activate_standalone
      subscription.mark_as_active!(timestamp)

      emit_fixed_charge_events

      after_commit do
        bill_subscription(skip_charges: true)
        notify_started
      end
    end

    def activate_for_upgrade
      Subscriptions::TerminateService.call(
        subscription: subscription.previous_subscription,
        upgrade: true
      )

      subscription.mark_as_active!(timestamp)

      emit_fixed_charge_events

      after_commit { notify_started }

      bill_upgrade_subscriptions
    end

    def billable_subscriptions
      @billable_subscriptions ||= begin
        billable = [subscription.previous_subscription]
        bill_new_in_advance = subscription.fixed_charges.pay_in_advance.any? ||
          (subscription.plan.pay_in_advance? && !subscription.in_trial_period?)
        billable << subscription if bill_new_in_advance
        billable
      end
    end

    def bill_upgrade_subscriptions
      after_commit do
        billing_at = Time.current + 1.second
        BillSubscriptionJob.perform_later(billable_subscriptions, billing_at.to_i, invoicing_reason: :upgrading)
        BillNonInvoiceableFeesJob.perform_later(billable_subscriptions, billing_at)
      end
    end

    def notify_started
      SendWebhookJob.perform_later("subscription.started", subscription)
      Utils::ActivityLog.produce(subscription, "subscription.started")

      return unless subscription.should_sync_hubspot_subscription?

      if upgrade?
        # The new upgrade subscription has no Hubspot record yet.
        Integrations::Aggregator::Subscriptions::Hubspot::CreateJob.perform_later(subscription:)
      elsif !during_creation
        # Skip when activating during subscription creation — CreateService
        # fires Hubspot::CreateJob after this, which captures the active state
        # and avoids a redundant Update that would race with Create.
        Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
      end
    end

    def emit_fixed_charge_events
      EmitFixedChargeEventsService.call!(
        subscriptions: [subscription],
        timestamp: subscription.started_at + 1.second
      )
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
