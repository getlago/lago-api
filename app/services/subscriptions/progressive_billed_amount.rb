# frozen_string_literal: true

module Subscriptions
  class ProgressiveBilledAmount < BaseService
    Result = BaseResult[:progressive_billed_amount, :progressive_billing_invoice, :to_credit_amount, :total_billed_amount_cents]

    def initialize(subscription:, timestamp: Time.current)
      @subscription = subscription
      @timestamp = timestamp

      super
    end

    def call
      result.progressive_billed_amount = 0
      result.total_billed_amount_cents = 0
      result.progressive_billing_invoice = nil
      result.to_credit_amount = 0

      invoice_subscriptions = InvoiceSubscription
        .where("charges_to_datetime > ?", timestamp)
        .where("charges_from_datetime <= ?", timestamp)
        .joins(:invoice)
        .merge(Invoice.progressive_billing)
        .merge(Invoice.finalized.or(Invoice.failed))
        .where(subscription: subscription)
        .order("invoices.issuing_date" => :desc, "invoices.created_at" => :desc)

      return result if invoice_subscriptions.blank?
      # total billed amount includes taxes and is spread between all invoices, where the billed amount is sum of
      # prepaid_credit_amount_cents and total_amount_cents
      total_billed_amount_cents = invoice_subscriptions.sum do |invoice_subscription|
        invoice_subscription.invoice.prepaid_credit_amount_cents +
          invoice_subscription.invoice.total_amount_cents
      end
      result.total_billed_amount_cents = total_billed_amount_cents
      invoice_subscription = invoice_subscriptions.first
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
