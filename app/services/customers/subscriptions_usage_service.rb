# frozen_string_literal: true

module Customers
  class SubscriptionsUsageService < BaseService
    Result = BaseResult[:fees, :billed_usage_amount_cents]

    def initialize(customer:, include_generating_invoices: false)
      @customer = customer
      @include_generating_invoices = include_generating_invoices
      super
    end

    def call
      fees = []
      total_usage_amount_cents = 0
      billed_usage_amount_cents = 0

      customer.active_subscriptions.each do |subscription|
        customer_usage_result = ::Invoices::CustomerUsageService.call(customer:, subscription:)
        return customer_usage_result if customer_usage_result.failure?

        invoice = customer_usage_result.invoice

        fees.concat(invoice.fees)
        total_usage_amount_cents += invoice.total_amount_cents
        billed_usage_amount_cents += compute_billed_usage_amount_cents(subscription, invoice)
      end

      result.fees = fees
      result.billed_usage_amount_cents = billed_usage_amount_cents
      result
    end

    private

    attr_reader :customer, :include_generating_invoices

    def compute_billed_usage_amount_cents(subscription, invoice)
      progressive_billed_total = ::Subscriptions::ProgressiveBilledAmount
        .call(subscription:, include_generating_invoices:)
        .total_billed_amount_cents

      paid_in_advance_fees = invoice.fees.select { |f| f.charge.pay_in_advance? && f.charge.invoiceable? }
      progressive_billed_total +
        # Invoice that is returned from CustomerUsageService includes the taxes in total_usage
        # so if the fees are already paid, we should exclude fees AND their taxes
        paid_in_advance_fees.sum(&:amount_cents) +
        paid_in_advance_fees.sum(&:taxes_amount_cents)
    end
  end
end
