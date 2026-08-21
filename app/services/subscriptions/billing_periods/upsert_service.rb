# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    # Upserts the billing period covering `timestamp` AND the following one,
    # so the realtime pipeline always finds a covering row for events arriving
    # right after a period rollover. Boundaries come from
    # Subscriptions::DatesService — the single source of truth for dates.
    class UpsertService < BaseService
      Result = BaseResult[:billing_periods]

      def initialize(subscription:, timestamp: Time.current)
        @subscription = subscription
        @timestamp = timestamp

        super
      end

      def call
        current_period = build_period(timestamp)
        if current_period.nil?
          result.billing_periods = []
          return result
        end

        periods = [current_period]
        next_period = build_period(current_period[:period_to] + 1.second)
        periods << next_period if next_period && next_period[:period_from] != current_period[:period_from]

        SubscriptionBillingPeriod.upsert_all(
          periods,
          unique_by: %i[subscription_id period_from]
        )

        result.billing_periods = periods
        result
      end

      private

      attr_reader :subscription, :timestamp

      def build_period(at)
        dates_service = Subscriptions::DatesService.new_instance(subscription, at, current_usage: true)

        period_from = dates_service.charges_from_datetime
        period_to = dates_service.charges_to_datetime
        return nil if period_from.nil? || period_to.nil?

        now = Time.current
        {
          organization_id: subscription.organization_id,
          subscription_id: subscription.id,
          customer_id: subscription.customer_id,
          period_from:,
          period_to:,
          created_at: now,
          updated_at: now
        }
      end
    end
  end
end
