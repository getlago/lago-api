# frozen_string_literal: true

module Fees
  class CreateFromUsageThresholdService < BaseService
    def initialize(usage_threshold:, invoice:, amount_cents:)
      @usage_threshold = usage_threshold
      @invoice = invoice
      @amount_cents = amount_cents

      super
    end

    def call
      fee = Fee.new(
        subscription: invoice.subscriptions.first,
        invoice:,
        usage_threshold:,
        invoice_display_name: usage_threshold.threshold_display_name,
        invoiceable: usage_threshold,
        amount_cents: amount_cents,
        amount_currency: invoice.currency,
        fee_type: :progressive_billing,
        units:,
        unit_amount_cents: unit_amount_cents,
        payment_status: :pending,
        taxes_amount_cents: 0,
        properties: {
          charges_from_datetime: invoice.invoice_subscriptions.first.charges_from_datetime,
          charges_to_datetime: invoice.invoice_subscriptions.first.charges_to_datetime,
          timestamp: invoice.invoice_subscriptions.first.timestamp
        }
      )

      taxes_result = Fees::ApplyTaxesService.call(fee:)
      taxes_result.raise_if_error!

      fee.save!
      result.fee = fee

      result
    end

    private

    attr_reader :usage_threshold, :invoice, :amount_cents

    def units
      return 1 unless usage_threshold.recurring?

      amount_cents.fdiv(usage_threshold.amount_cents)
    end

    def unit_amount_cents
      return amount_cents unless usage_threshold.recurring?

      usage_threshold.amount_cents
    end
  end
end
