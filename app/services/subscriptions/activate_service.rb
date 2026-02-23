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
          if subscription.payment_gated? && !subscription.in_trial_period?
            subscription.mark_as_activating!(Time.zone.at(timestamp))
          else
            subscription.mark_as_active!(Time.zone.at(timestamp))
          end

          fixed_charge_timestamp = subscription.started_at + 1.second

          EmitFixedChargeEventsService.call!(
            subscriptions: [subscription],
            timestamp: fixed_charge_timestamp
          )

          if subscription.should_sync_hubspot_subscription?
            Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
          end

          if subscription.activating?
            BillSubscriptionJob.perform_later(
              [subscription],
              timestamp,
              invoicing_reason: :subscription_starting
            )
            Subscriptions::ActivationTimeoutJob.set(
              wait_until: subscription.activation_timeout_at
            ).perform_later(subscription)
            SendWebhookJob.perform_later("subscription.activating", subscription)
            Utils::ActivityLog.produce(subscription, "subscription.activating")
          else
            SendWebhookJob.perform_later("subscription.started", subscription)
            Utils::ActivityLog.produce(subscription, "subscription.started")

            if subscription.plan.pay_in_advance? && !subscription.in_trial_period?
              BillSubscriptionJob.perform_later([subscription], timestamp, invoicing_reason: :subscription_starting)
            elsif subscription.fixed_charges.pay_in_advance.any?
              Invoices::CreatePayInAdvanceFixedChargesJob.perform_later(subscription, fixed_charge_timestamp)
            end
          end
        end
    end

    private

    attr_reader :timestamp
  end
end
