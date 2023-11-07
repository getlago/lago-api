# frozen_string_literal: true

module CreditNotes
  class ApplyTaxesService < BaseService
    def initialize(invoice:, items:)
      @invoice = invoice
      @items = items

      super
    end

    def call
      result.applied_taxes = []
      result.coupons_adjustment_amount_cents = coupons_adjustment_amount_cents

      applied_taxes_amount_cents = 0
      taxes_rate = 0

      applicable_taxes.each do |tax|
        invoice_applied_tax = find_invoice_applied_tax(tax)

        applied_tax = CreditNote::AppliedTax.new(
          tax:,
          tax_description: invoice_applied_tax&.tax_description || tax.description,
          tax_code: invoice_applied_tax&.tax_code || tax.code,
          tax_name: invoice_applied_tax&.tax_name || tax.name,
          tax_rate: invoice_applied_tax&.tax_rate || tax.rate,
          amount_currency: invoice.currency,
        )
        result.applied_taxes << applied_tax

        base_amount_cents = compute_base_amount_cents(tax)
        applied_tax.base_amount_cents = base_amount_cents.round

        tax_amount_cents = (base_amount_cents * tax.rate).fdiv(100)
        applied_tax.amount_cents = tax_amount_cents.round

        applied_taxes_amount_cents += tax_amount_cents
        taxes_rate += pro_rated_taxes_rate(tax)
      end

      result.taxes_amount_cents = applied_taxes_amount_cents
      result.taxes_rate = taxes_rate.round(5)

      result
    end

    private

    attr_reader :invoice, :items

    delegate :organization, to: :invoice

    def applicable_taxes
      organization.taxes.where(id: indexed_items.keys)
    end

    # NOTE: indexes the credit note fees by taxes.
    #       Example output will be: { tax1 => [fee1, fee2], tax2 => [fee2] }
    def indexed_items
      @indexed_items ||= items.each_with_object({}) do |item, applied_taxes|
        item.fee.applied_taxes.each do |applied_tax|
          applied_taxes[applied_tax.tax_id] ||= []
          applied_taxes[applied_tax.tax_id] << item
        end
      end
    end

    def items_amount_cents
      @items_amount_cents ||= items.sum(&:precise_amount_cents)
    end

    def coupons_adjustment_amount_cents
      return 0 if invoice.version_number < Invoice::COUPON_BEFORE_VAT_VERSION

      items.sum do |item|
        item_fee_rate = item.precise_amount_cents.fdiv(item.fee.amount_cents)
        item.fee.precise_coupons_amount_cents * item_fee_rate
      end
    end

    def compute_base_amount_cents(tax)
      indexed_items[tax.id].map do |item|
        # NOTE: Part of the item taken from the fee amount
        item_fee_rate = item.precise_amount_cents.fdiv(item.fee.amount_cents)

        # NOTE: Part of the coupons applied to the item
        prorated_coupon_amount = item.fee.precise_coupons_amount_cents * item_fee_rate

        item.precise_amount_cents - prorated_coupon_amount
      end.sum
    end

    # NOTE: Tax might not be applied to all items of the credit note.
    #       In order to compute the credit_note#taxes_rate, we have to apply
    #       a pro-rata of the items attached to the tax on the total items amount
    def pro_rated_taxes_rate(tax)
      tax_items_amount_cents = compute_base_amount_cents(tax)
      total_items_amount_cents = items_amount_cents - result.coupons_adjustment_amount_cents

      items_rate = tax_items_amount_cents.fdiv(total_items_amount_cents)

      items_rate * tax.rate
    end

    def find_invoice_applied_tax(tax)
      invoice.applied_taxes.find_by(tax_id: tax.id)
    end
  end
end
