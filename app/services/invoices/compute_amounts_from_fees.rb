# frozen_string_literal: true

module Invoices
  class ComputeAmountsFromFees < BaseService
    def initialize(invoice:, provider_taxes: nil)
      @invoice = invoice
      @provider_taxes = provider_taxes

      super
    end

    def call
      if !invoice.one_off? || invoice.failed?
        invoice.fees.each do |fee|
          taxes_result = if provider_taxes && customer_provider_taxation?
            Fees::ApplyProviderTaxesService.call(fee:, fee_taxes: fee_taxes(fee))
          else
            Fees::ApplyTaxesService.call(fee:)
          end
          taxes_result.raise_if_error!
          fee.save!
        end
      end

      invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
      invoice.coupons_amount_cents = invoice.credits.coupon_kind.sum(:amount_cents)

      invoice.sub_total_excluding_taxes_amount_cents = (
        invoice.fees_amount_cents - invoice.progressive_billing_credit_amount_cents - invoice.coupons_amount_cents
      )

      taxes_result = if provider_taxes && customer_provider_taxation?
        Invoices::ApplyProviderTaxesService.call(invoice:, provider_taxes:)
      else
        Invoices::ApplyTaxesService.call(invoice:)
      end
      taxes_result.raise_if_error!

      invoice.sub_total_including_taxes_amount_cents = (
        invoice.sub_total_excluding_taxes_amount_cents + invoice.taxes_amount_cents
      )
      invoice.total_amount_cents = (
        invoice.sub_total_including_taxes_amount_cents - invoice.credit_notes_amount_cents
      )

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice, :provider_taxes

    def customer_provider_taxation?
      @customer_provider_taxation ||= invoice.customer.anrok_customer
    end

    def fee_taxes(fee)
      provider_taxes.find { |item| item.item_id == fee.item_id }
    end
  end
end
