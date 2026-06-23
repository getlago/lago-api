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
      return result if creditable_invoice_issued?

      raise MissingCreditableInvoiceError,
        "subscription #{subscription.id} has no usable invoice for the period at #{timestamp.iso8601}: " \
        "BillSubscriptionJob must finish successfully and produce the period invoice before " \
        "Subscriptions::ActivationRules::Payment::ResolveJob is re-executed"
    end

    private

    attr_reader :subscription, :timestamp

    def creditable_invoice_issued?
      PayInAdvanceInvoiceIssuedService.call(subscription:, timestamp:).issued &&
        !period_invoice_voided?
    end

    def period_invoice_voided?
      subscription.last_subscription_fee&.invoice&.voided? || false
    end
  end
end
