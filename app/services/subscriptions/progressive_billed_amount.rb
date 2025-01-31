# frozen_string_literal: true

module Subscriptions
  class ProgressiveBilledAmount < BaseService
    def initialize(subscription:, timestamp: Time.current)
      @subscription = subscription
      @timestamp = timestamp

      super
    end

    def call
      result.progressive_billed_amount = 0
      result.progressive_billing_invoice = nil
      result.to_credit_amount = 0

      invoice_subscription = InvoiceSubscription
        .where("charges_to_datetime > ?", timestamp)
        .where("charges_from_datetime <= ?", timestamp)
        .joins(:invoice)
        .merge(Invoice.progressive_billing)
        .merge(Invoice.finalized.or(Invoice.failed))
        .where(subscription: subscription)
        .order("invoices.issuing_date" => :desc, "invoices.created_at" => :desc).first

      return result unless invoice_subscription
      invoice = invoice_subscription.invoice
      result.progressive_billing_invoice = invoice
      result.progressive_billed_amount = result.progressive_billing_invoice.fees_amount_cents
      result.to_credit_amount = invoice.fees_amount_cents

      if invoice.progressive_billing_credits.exists? || invoice.credit_notes.available.exists?
        result.to_credit_amount -= invoice.progressive_billing_credits.sum(:amount_cents)
        result.to_credit_amount -= invoice.credit_notes.available.sum(:credit_amount_cents)

        # if for some reason this goes below zero, it should be zero.
        result.to_credit_amount = 0 if result.to_credit_amount.negative?
      end

      result
    end

    private

    attr_reader :subscription, :timestamp
  end
end
