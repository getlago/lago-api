# frozen_string_literal: true

module Subscriptions
  class EnsureBilledForPeriodService < BaseService
    class NotBilledError < StandardError; end

    Result = BaseResult

    def initialize(subscription:, timestamp:)
      @subscription = subscription
      @timestamp = timestamp
      super
    end

    def call
      return result unless subscription.active?
      return result unless subscription.plan.pay_in_advance?

      BillSubscriptionJob.perform_now([subscription], timestamp.to_i, invoicing_reason: :subscription_periodic)

      return result if period_billed?

      raise NotBilledError,
        "subscription #{subscription.id} has no usable invoice for the period at #{timestamp.iso8601}"
    end

    private

    attr_reader :subscription, :timestamp

    def period_billed?
      subscription.invoice_subscriptions
        .recurring
        .joins(:invoice)
        .where("invoice_subscriptions.from_datetime <= :ts AND invoice_subscriptions.to_datetime > :ts", ts: timestamp)
        .where.not(invoices: {status: [Invoice.statuses[:generating], Invoice.statuses[:failed]]})
        .exists?
    end
  end
end
