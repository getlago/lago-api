# frozen_string_literal: true

module Invoices
  module ProgressiveBilling
    class UsageThresholdService < BaseService
      def initialize(sorted_usage_thresholds:, lifetime_usage:, timestamp: Time.current)
        @sorted_usage_thresholds = sorted_usage_thresholds
        @lifetime_usage = lifetime_usage

        super(timestamp:)
      end

      private

      attr_reader :sorted_usage_thresholds, :lifetime_usage

      delegate :subscription, to: :lifetime_usage

      def idempotency_values
        {
          # this is required to be here for recurring thresholds. as we'll not have credits across billing periods, this is not enough information for uniqueness otherwise.
          invoiced_usage: lifetime_usage.invoiced_usage_amount_cents,
          threshold_amount: sorted_usage_thresholds.last.amount_cents
        }
      end

      def after_fees_created
        sorted_usage_thresholds.each do |usage_threshold|
          AppliedUsageThreshold.create!(
            organization_id: lifetime_usage.organization_id,
            invoice:,
            usage_threshold:,
            lifetime_usage_amount_cents: lifetime_usage.total_amount_cents
          )
        end
      end

      def after_progressive_billing_credits_applied(credits)
        if credits.any? && sorted_usage_thresholds.last.recurring?
          Idempotency.unique!(invoice, previous_progressive_billing_invoice_id: credits.first.progressive_billing_invoice_id)
        end
      end
    end
  end
end
