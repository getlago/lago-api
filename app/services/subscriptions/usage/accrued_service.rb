# frozen_string_literal: true

module Subscriptions
  module Usage
    class AccruedService < BaseService
      def initialize(subscription:, timestamp: Time.current)
        @subscription = subscription
        @timestamp = timestamp

        super
      end

      def call
        result.amount_cents = accrued_fees_amount_cents + current_usage
        result
      end

      private

      attr_reader :subscription, :timestamp

      def accrued_fees_amount_cents
        Fee
          .joins(:invoice, charge: :billable_metric)
          .charge
          .where(subscription_id: subscription.id)
          .merge(Invoice.finalized)
          .where(invoices: {issuing_date: ...timestamp.to_date})
          .where(charges: {pay_in_advance: false})
          .where(billable_metrics: {recurring: false})
          .sum(:amount_cents)
      end

      def current_usage
        Subscriptions::Usage::PreAggregatedService.new(subscription: subscription).call.amount_cents
      end
    end
  end
end
