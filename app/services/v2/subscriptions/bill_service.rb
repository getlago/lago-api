# frozen_string_literal: true

module V2
  module Subscriptions
    # Manual billing trigger for the product-catalog engine, so the product team can
    # fast-forward one or more subscriptions to a date range and inspect the result synchronously
    # (the invoices land in the response instead of waiting for the clock).
    #
    # Runs the producer + consumer for `range`, emitting the cycles that would
    # have been billed during it.
    #
    # Only product_catalog subscriptions are billed by this engine, so the call is rejected
    # if any of them is on a legacy plan rather than silently skipping it.
    class BillService < BaseService
      Result = BaseResult[:invoices]

      def initialize(subscriptions:, start_on: nil, end_on: nil)
        @subscriptions = Array.wrap(subscriptions)
        @start_on = start_on
        @end_on = end_on
        super
      end

      def call
        return result.not_found_failure!(resource: "subscription") if subscriptions.empty?

        if subscriptions.any? { |subscription| !subscription.plan.product_catalog? }
          return result.single_validation_failure!(field: :subscription, error_code: "not_a_product_catalog_subscription")
        end

        billing_range
        return result if result.error

        result.invoices = []

        bill_all
        result
      end

      private

      attr_reader :subscriptions, :start_on, :end_on

      # The engine bills per customer (ScheduleService and ProcessService are both
      # customer-scoped, so one pass emits every due cycle that customer has). Billing once
      # per distinct customer therefore covers every subscription passed in, and avoids
      # follow-up passes that would find nothing left to bill.
      def bill_all
        subscriptions.uniq(&:customer_id).each do |subscription|
          billing = BillingCycles::BillSubscriptionService.call(subscription:, range: billing_range)
          return result.fail_with_error!(billing.error) unless billing.success?

          result.invoices.concat(billing.invoices)
        end
      end

      def billing_range
        @billing_range ||= parse_range
      end

      def parse_range
        now = Time.current
        return now..now if end_on.blank?

        parsed_end_on = parse_bill_date(end_on)
        parsed_start_on = if start_on.present?
          parse_bill_date(start_on)
        else
          parsed_end_on&.yesterday
        end

        from = parsed_start_on&.beginning_of_day&.utc
        to = parsed_end_on&.end_of_day&.utc
        return invalid_range unless from && to

        return invalid_range if from > to

        from..to
      end

      def parse_bill_date(value)
        value.to_s.delete('"').to_date
      rescue Date::Error
        nil
      end

      def invalid_range
        result.single_validation_failure!(field: :range, error_code: "invalid_date_range")
        nil
      end
    end
  end
end
