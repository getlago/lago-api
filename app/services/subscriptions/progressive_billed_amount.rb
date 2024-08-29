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

      invoice_subscription = InvoiceSubscription
        .where("charges_to_datetime > ?", timestamp)
        .where("charges_from_datetime <= ?", timestamp)
        .joins(:invoice)
        .merge(Invoice.progressive_billing)
        .merge(Invoice.finalized)
        .where(subscription: subscription)
        .order("invoices.issuing_date" => :desc, "invoices.created_at" => :desc).first

      return result unless invoice_subscription
      result.progressive_billing_invoice = invoice_subscription.invoice
      result.progressive_billed_amount = result.progressive_billing_invoice.fees_amount_cents

      result
    end

    private

    attr_reader :subscription, :timestamp
  end
end
