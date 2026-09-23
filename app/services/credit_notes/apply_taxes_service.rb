# frozen_string_literal: true

module CreditNotes
  class ApplyTaxesService < BaseService
    Result = BaseResult[:applied_taxes, :coupons_adjustment_amount_cents, :precise_taxes_amount_cents, :taxes_amount_cents, :taxes_rate]

    def initialize(invoice:, items:)
      @invoice = invoice
      @items = items

      super
    end

    def call
      result.applied_taxes = []
      result.coupons_adjustment_amount_cents = coupons_adjustment_amount_cents

      applied_taxes_amount_cents = 0
      precise_applied_taxes_amount_cents = 0
      taxes_rate = 0

      @indexed_items = index_items_by_invoice_tax
      return result unless @indexed_items

      indexed_items.each do |tax_key, entry|
        invoice_applied_tax = entry[:invoice_applied_tax]

        applied_tax = CreditNote::AppliedTax.new(
          organization_id: invoice.organization_id,
          tax: invoice_applied_tax.tax,
          tax_description: invoice_applied_tax.tax_description,
          tax_code: invoice_applied_tax.tax_code,
          tax_name: invoice_applied_tax.tax_name,
          tax_rate: invoice_applied_tax.tax_rate,
          amount_currency: invoice.currency
        )
        result.applied_taxes << applied_tax

        base_amount_cents = compute_base_amount_cents(tax_key)
        applied_tax.base_amount_cents = (base_amount_cents * taxes_base_rate(invoice_applied_tax)).round
        precise_base_amount_cents = (base_amount_cents * taxes_base_rate(invoice_applied_tax))
        precise_tax_amount_cents = (precise_base_amount_cents * invoice_applied_tax.tax_rate).fdiv(100)
        applied_tax.amount_cents += precise_tax_amount_cents.round

        precise_applied_taxes_amount_cents += precise_tax_amount_cents
        applied_taxes_amount_cents += precise_tax_amount_cents.round
        taxes_rate += pro_rated_taxes_rate(applied_tax, tax_key)
      end

      result.precise_taxes_amount_cents = precise_applied_taxes_amount_cents
      result.taxes_amount_cents = applied_taxes_amount_cents
      result.taxes_rate = taxes_rate.round(5)

      result
    end

    private

    attr_reader :invoice, :items

    delegate :organization, to: :invoice

    attr_reader :indexed_items

    # NOTE: indexes the credit note items by the invoice applied tax their fee taxes resolve to,
    #       keyed by that invoice tax's code and rate. Keying on the resolved invoice tax, not on
    #       the fee tax, lets two fee taxes that resolve to the same invoice tax share a single
    #       credit note tax instead of colliding on the (credit_note_id, tax_code, tax_rate) index.
    #       Returns nil, with the failure recorded on the result, when a fee tax cannot be resolved.
    #       Example output: { ["vat", 20.0] => { invoice_applied_tax: tax, items: [item1, item2] } }
    def index_items_by_invoice_tax
      items.each_with_object({}) do |item, index|
        item.fee.applied_taxes.each do |fee_applied_tax|
          invoice_applied_tax = find_invoice_applied_tax(fee_applied_tax)
          return nil unless invoice_applied_tax

          entry = index[tax_key(invoice_applied_tax)] ||= {invoice_applied_tax:, items: []}
          entry[:items] << item unless entry[:items].include?(item)
        end
      end
    end

    def items_amount_cents
      @items_amount_cents ||= items.sum(&:precise_amount_cents)
    end

    def coupons_adjustment_amount_cents
      return 0 if invoice.version_number < Invoice::COUPON_BEFORE_VAT_VERSION

      items.sum do |item|
        item_fee_rate = item.fee.amount_cents.zero? ? 0 : item.precise_amount_cents.fdiv(item.fee.amount_cents)
        item.fee.precise_coupons_amount_cents * item_fee_rate
      end
    end

    def compute_base_amount_cents(tax_key)
      indexed_items[tax_key][:items].map do |item|
        # NOTE: Part of the item taken from the fee amount
        item_fee_rate = item.fee.amount_cents.zero? ? 0 : item.precise_amount_cents.fdiv(item.fee.amount_cents)

        # NOTE: Part of the coupons applied to the item
        prorated_coupon_amount = item.fee.precise_coupons_amount_cents * item_fee_rate

        item.precise_amount_cents - prorated_coupon_amount
      end.sum
    end

    # NOTE: Tax might not be applied to all items of the credit note.
    #       In order to compute the credit_note#taxes_rate, we have to apply
    #       a pro-rata of the items attached to the tax on the total items amount
    def pro_rated_taxes_rate(applied_tax, tax_key)
      tax_items_amount_cents = compute_base_amount_cents(tax_key)
      total_items_amount_cents = items_amount_cents - result.coupons_adjustment_amount_cents

      items_rate = total_items_amount_cents.zero? ? 0 : tax_items_amount_cents.fdiv(total_items_amount_cents)

      items_rate * applied_tax.tax_rate
    end

    # NOTE: a fee tax resolves to the invoice tax with the same code and rate. When no invoice tax
    #       has that rate (the fee and the invoice were taxed at different rates, e.g. the tax rate
    #       changed in between), it falls back to the invoice tax carrying the same code, but only
    #       if exactly one does: several invoice taxes sharing a code is the provider multi-rate
    #       case, where the rate is the only thing telling them apart.
    def find_invoice_applied_tax(fee_applied_tax)
      key = tax_key(fee_applied_tax)
      exact_match = invoice_applied_taxes.find { |applied_tax| tax_key(applied_tax) == key }
      return exact_match if exact_match

      code_matches = invoice_applied_taxes.select { |applied_tax| applied_tax.tax_code == fee_applied_tax.tax_code }
      return code_matches.first if code_matches.one?

      result.service_failure!(
        code: "invoice_applied_tax_not_found",
        message: "Invoice #{invoice.id} has no applied tax matching #{key.join(", ")}"
      )

      nil
    end

    def invoice_applied_taxes
      @invoice_applied_taxes ||= invoice.applied_taxes.to_a
    end

    def tax_key(applied_tax)
      [applied_tax.tax_code, applied_tax.tax_rate]
    end

    def taxes_base_rate(applied_tax)
      return 1 if applied_tax.fees_amount_cents.blank? || applied_tax.fees_amount_cents.zero?

      applied_tax.taxable_amount_cents.fdiv(applied_tax.fees_amount_cents)
    end
  end
end
