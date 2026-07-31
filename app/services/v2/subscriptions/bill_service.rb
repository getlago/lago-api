# frozen_string_literal: true

module V2
  module Subscriptions
    # Manual billing trigger for the product-catalog engine, so the product team can
    # fast-forward one or more subscriptions to a date and inspect the result synchronously
    # (the invoices land in the response instead of waiting for the clock).
    #
    # - terminate: false => run the producer + consumer up to `timestamp`, emitting the
    #   cycles that would have been billed by then.
    # - terminate: true  => terminate each subscription at `timestamp` (final prorated cycle
    #   + advance credit notes), then bill inline. TerminateService also enqueues the billing
    #   job after commit; running it inline here just materialises the invoice in the
    #   response, and the async job then finds nothing left to bill.
    #
    # Only product_catalog subscriptions are billed by this engine, so the call is rejected
    # if any of them is on a legacy plan rather than silently skipping it.
    class BillService < BaseService
      Result = BaseResult[:invoices, :credit_notes]

      def initialize(subscriptions:, timestamp: nil, terminate: false)
        @subscriptions = Array.wrap(subscriptions)
        @timestamp = timestamp
        @terminate = terminate
        super
      end

      def call
        return result.not_found_failure!(resource: "subscription") if subscriptions.empty?

        if subscriptions.any? { |subscription| !subscription.plan.product_catalog? }
          return result.single_validation_failure!(field: :subscription, error_code: "not_a_product_catalog_subscription")
        end

        at = parse_timestamp
        return result if result.error

        result.invoices = []
        result.credit_notes = []

        terminate_all(at) if terminate
        return result if result.error

        bill_all(at)
        result
      end

      private

      attr_reader :subscriptions, :timestamp, :terminate

      def terminate_all(at)
        subscriptions.each do |subscription|
          termination = ::V2::Subscriptions::TerminateService.call(subscription:, terminated_at: at)
          return result.fail_with_error!(termination.error) unless termination.success?

          result.credit_notes.concat(Array.wrap(termination.credit_notes))
        end
      end

      # The engine bills per customer (ScheduleService and ProcessService are both
      # customer-scoped, so one pass emits every due cycle that customer has). Billing once
      # per distinct customer therefore covers every subscription passed in, and avoids
      # follow-up passes that would find nothing left to bill.
      def bill_all(at)
        subscriptions.uniq(&:customer_id).each do |subscription|
          billing = BillingCycles::BillSubscriptionService.call(subscription:, up_to: at)
          return result.fail_with_error!(billing.error) unless billing.success?

          result.invoices.concat(billing.invoices)
        end
      end

      # Accepts an ISO8601 datetime/date ("2026-09-01T00:00:00Z", "2026-09-01") or an epoch
      # second ("1756684800"); defaults to now when omitted.
      def parse_timestamp
        return Time.current if timestamp.blank?

        value = timestamp.to_s
        return Time.zone.at(Integer(value)) if value.match?(/\A\d+\z/)

        Time.zone.parse(value) || invalid_timestamp
      rescue ArgumentError, TypeError
        invalid_timestamp
      end

      def invalid_timestamp
        result.single_validation_failure!(field: :timestamp, error_code: "invalid_timestamp")
        nil
      end
    end
  end
end
