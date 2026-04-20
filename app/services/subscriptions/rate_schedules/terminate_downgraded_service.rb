# frozen_string_literal: true

module Subscriptions
  module RateSchedules
    class TerminateDowngradedService < BaseService
      Result = BaseResult[:subscription]

      def initialize(subscription:, timestamp:)
        @subscription = subscription
        @timestamp = timestamp
        @rotation_date = Time.zone.at(timestamp)
        super
      end

      def call
        return result unless next_subscription
        return result unless next_subscription.pending?

        ActiveRecord::Base.transaction do
          terminate_current_subscription
          activate_next_subscription
        end

        bill_subscriptions
        log_and_send_webhooks

        result.subscription = next_subscription
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :subscription, :timestamp, :rotation_date

      def next_subscription
        subscription.next_subscription
      end

      def terminate_current_subscription
        subscription.mark_as_terminated!(rotation_date)

        if subscription.should_sync_hubspot_subscription?
          Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
        end
      end

      def activate_next_subscription
        next_subscription.mark_as_active!(rotation_date)

        # Will we need it or will we have a different version of it?
        EmitFixedChargeEventsService.call!(
          subscriptions: [next_subscription],
          timestamp: next_subscription.started_at + 1.second
        )

        if next_subscription.should_sync_hubspot_subscription?
          Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(next_subscription)
        end
      end

      def log_and_send_webhooks
        SendWebhookJob.perform_later("subscription.terminated", subscription)
        Utils::ActivityLog.produce(subscription, "subscription.terminated")

        SendWebhookJob.perform_later("subscription.started", next_subscription)
        Utils::ActivityLog.produce(next_subscription, "subscription.started")
      end

      def bill_subscriptions
        Invoices::RateSchedulesBillingJob.perform_later(
          billable_rate_schedules,
          timestamp,
          invoicing_reason: :upgrading
        )
      end

      def billable_rate_schedules
        rate_schedules = subscription.subscription_rate_schedules.to_a

        if next_subscription.pay_in_advance? || next_subscription.has_pay_in_advance_fixed_items?
          rate_schedules += next_subscription.subscription_rate_schedules.to_a
        end

        rate_schedules
      end
    end
  end
end
