# frozen_string_literal: true

module Subscriptions
  class GatedActivationService < BaseService
    def initialize(subscription:)
      super
    end

    def call
      return if no_rules
      return if subscription.starting_in_the_future?
      return if subscription.active?
      return if subscription.activating?
      return if nothing_to_bill_today?

      new_subscription.mark_as_activating!

      EmitFixedChargeEventsService.call!(
        subscriptions: [new_subscription],
        timestamp: new_subscription.activating_at + 1.second
      )

      after_commit do
        if fixed_charges_billed_today?(new_subscription)
          Invoices::CreatePayInAdvanceFixedChargesJob.perform_later(
            new_subscription,
            new_subscription.activation_start_at + 1.second
          )
        else 
          BillSubscriptionJob.perform_later(
            [new_subscription],
            Time.zone.now.to_i,
            invoicing_reason: :subscription_starting
          )
        end

        SendWebhookJob.perform_later("subscription.activating", new_subscription)
        Utils::ActivityLog.produce(new_subscription, "subscription.activating")

        if new_subscription.should_sync_hubspot_subscription?
          Integrations::Aggregator::Subscriptions::Hubspot::CreateJob.perform_later(subscription: new_subscription)
        end
      end

      new_subscription
    end
  end

  private

  def nothing_to_bill_today?
    return true if subscription.in_trial_period? && subscription.fixed_charges.pay_in_advance.none?
    return false if subscription.plan.pay_in_advance?

    return subscription.fixed_charges.pay_in_advance.none?
  end
end
