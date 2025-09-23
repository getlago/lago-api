# frozen_string_literal: true

module Invoices
  class ComputeAmountsFromFees < BaseService
    def initialize(invoice:, provider_taxes: nil)
      @invoice = invoice
      @provider_taxes = provider_taxes

      super
    end

    def call
      if should_apply_fee_taxes?
        invoice.fees.each do |fee|
          if provider_taxes && customer_provider_taxation? && invoice.should_apply_provider_tax?
            Fees::ApplyProviderTaxesService.call!(fee:, fee_taxes: fee_taxes(fee))
          else
            Fees::ApplyTaxesService.call!(fee:)
          end

          fee.save!
        end
      end

      invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
      invoice.coupons_amount_cents = invoice.credits.coupon_kind.sum(:amount_cents)

      invoice.sub_total_excluding_taxes_amount_cents = (
        invoice.fees_amount_cents - invoice.progressive_billing_credit_amount_cents - invoice.coupons_amount_cents
      )

      if customer_provider_taxation? && invoice.should_apply_provider_tax?
        Invoices::ApplyProviderTaxesService.call!(invoice:, provider_taxes:)
      else
        Invoices::ApplyTaxesService.call!(invoice:)
      end

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
      @customer_provider_taxation ||= invoice.customer.tax_customer
    end

    def fee_taxes(fee)
      provider_taxes.find { |item| item.item_id == fee.id }
    end

    def should_apply_fee_taxes?
      return false if invoice.one_off? && !(invoice.failed? || invoice.pending?)
      return false if invoice.advance_charges?

      true
    end
  end
end
