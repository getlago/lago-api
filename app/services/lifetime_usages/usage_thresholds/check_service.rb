# frozen_string_literal: true

module LifetimeUsages
  module UsageThresholds
    class CheckService < BaseService
      def initialize(lifetime_usage:)
        @lifetime_usage = lifetime_usage
        @thresholds = lifetime_usage.subscription.usage_thresholds
        super
      end

      def call
        result.passed_thresholds = []

        fixed_thresholds = thresholds.not_recurring.order(:amount_cents)
        # There is only 1 recurring threshold, `first` will return it or nil
        recurring_threshold = thresholds.recurring.first

        progressive_billed_amount = subscription.invoices.progressive_billing.sum(:amount_cents)

        # Calculate the actual current usage, we need to substract the already billed progressive amount
        # as we might be passing the threshold multiple times per period
        actual_current_usage = lifetime_usage.current_usage_amount_cents - progressive_billed_amount
        invoiced_usage = lifetime_usage.invoiced_usage_amount_cents

        # Get the largest threshold amount
        # in case there are no fixed_thresholds, this will return nil which to_i will convert to 0
        largest_threshold_amount = fixed_thresholds.maximum(:amount_cents).to_i
        total_usage = invoiced_usage + actual_current_usage

        # First check the fixed thresholds
        if invoiced_usage < largest_threshold_amount
          # we're below some thresholds, filter out those that we've already invoiced.
          # and keep those that we've passed based on total_usage.
          result.passed_thresholds += fixed_thresholds.select do |threshold|
            threshold.amount_cents > invoiced_usage && threshold.amount_cents <= total_usage
          end
        end

        # Finally check the recurring threshold
        if recurring_threshold && total_usage - largest_threshold_amount > recurring_threshold.amount_cents
          result.passed_thresholds << recurring_threshold
        end

        result
      end

      private

      attr_reader :lifetime_usage, :thresholds
    end
  end
end
