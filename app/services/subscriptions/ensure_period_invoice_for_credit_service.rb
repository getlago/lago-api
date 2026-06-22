# frozen_string_literal: true

module Subscriptions
  class EnsurePeriodInvoiceForCreditService < BaseService
    class MissingCreditableInvoiceError < StandardError; end

    Result = BaseResult

    def initialize(subscription:, timestamp:)
      @subscription = subscription
      @timestamp = timestamp
      super
    end

    def call
      return result unless subscription.plan.pay_in_advance?
      return result if subscription.on_termination_credit_note_skip?
      return result if period_billed?

      raise MissingCreditableInvoiceError,
        "subscription #{subscription.id} has no usable invoice for the period at #{timestamp.iso8601}: " \
        "BillSubscriptionJob must finish successfully and produce the period invoice before " \
        "Subscriptions::ActivationRules::Payment::ResolveJob is re-executed"
    end

    private

    attr_reader :subscription, :timestamp

    def period_billed?
      subscription.invoice_subscriptions
        .recurring
        .joins(:invoice)
        .where("invoice_subscriptions.from_datetime <= :ts AND invoice_subscriptions.to_datetime > :ts", ts: timestamp)
        .where.not(invoices: {status: Invoice.statuses[:voided]})
        .exists?
    end
  end
end
