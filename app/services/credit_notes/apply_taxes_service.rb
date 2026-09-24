# frozen_string_literal: true

module CreditNotes
  class ApplyTaxesService < BaseService
    Result = BaseResult[:applied_taxes, :coupons_adjustment_amount_cents, :precise_taxes_amount_cents, :taxes_amount_cents, :taxes_rate, :precise_tax_amounts]

    def initialize(invoice:, items:)
      @invoice = invoice
      @items = items

      super
    end

    def call
      result.applied_taxes = []
      result.precise_tax_amounts = []
      result.coupons_adjustment_amount_cents = coupons_adjustment_amount_cents

      @indexed_items = index_items_by_invoice_tax
      return result unless @indexed_items

      indexed_items.each do |tax_key, entry|
        invoice_applied_tax = entry[:invoice_applied_tax]
        precise_base_amount_cents = base_amounts.fetch(tax_key) * taxes_base_rate(invoice_applied_tax)
        precise_tax_amount_cents = if invoice_applied_tax.provider_tax?
          booked_tax_to_credit(tax_key, entry[:items].uniq)
        else
          (precise_base_amount_cents * invoice_applied_tax.tax_rate).fdiv(100)
        end

        result.applied_taxes << build_applied_tax(
          invoice_applied_tax,
          base_amount_cents: precise_base_amount_cents,
          tax_amount_cents: precise_tax_amount_cents
        )
        result.precise_tax_amounts << precise_tax_amount_cents
      end

      result.precise_taxes_amount_cents = result.precise_tax_amounts.sum
      result.taxes_amount_cents = result.applied_taxes.sum(&:amount_cents)
      result.taxes_rate = result.applied_taxes.sum { |tax| pro_rated_taxes_rate(tax) }.round(5)

      result
    end

    private

    attr_reader :invoice, :items

    delegate :organization, to: :invoice

    attr_reader :indexed_items

    def build_applied_tax(invoice_applied_tax, base_amount_cents:, tax_amount_cents:)
      CreditNote::AppliedTax.new(
        organization_id: invoice.organization_id,
        tax: invoice_applied_tax.tax,
        tax_description: invoice_applied_tax.tax_description,
        tax_code: invoice_applied_tax.tax_code,
        tax_name: invoice_applied_tax.tax_name,
        tax_rate: invoice_applied_tax.tax_rate,
        amount_currency: invoice.currency,
        base_amount_cents: base_amount_cents.round,
        amount_cents: tax_amount_cents.round
      )
    end

    def booked_tax_to_credit(tax_key, items)
      booked_tax = booked_tax_by_fee(tax_key)

      items.sum { |item| credited_portion(booked_tax.fetch(item.fee_id), item) }
    end

    def credited_portion(fee_amount_cents, item)
      if item.fee.amount_cents.zero?
        0.to_d
      else
        fee_amount_cents * item.precise_amount_cents / item.fee.amount_cents
      end
    end

    def booked_tax_by_fee(tax_key)
      fee_taxes = fee_taxes_by_key.fetch(tax_key).group_by(&:fee_id)
      booked_tax = Integrations::Aggregator::Taxes::Allocation.by_group(invoice_tax_by_key.fetch(tax_key), fee_taxes.values)

      fee_taxes.keys.zip(booked_tax).to_h
    end

    # Invoices booked before provider amounts were stored rounded each fee tax on its own,
    # so their fee taxes can add up to less than the tax charged on the invoice.
    def invoice_tax_by_key
      @invoice_tax_by_key ||= begin
        invoice_taxes = invoice_applied_taxes.group_by { |tax| tax_key(tax) }.sort_by(&:first).to_h
        weights = invoice_tax_weights(invoice_taxes)
        invoice_tax = Integrations::Aggregator::Taxes::Allocation.call(invoice.taxes_amount_cents, weights)

        invoice_taxes.keys.zip(invoice_tax).to_h
      end
    end

    def invoice_tax_weights(invoice_taxes)
      booked_weights = invoice_taxes.values.map { |taxes| taxes.sum(&:amount_cents) }
      return booked_weights if booked_weights.sum == invoice.taxes_amount_cents

      exact_weights = invoice_taxes.keys.map { |key| fee_taxes_by_key.fetch(key, []).sum(&:precise_amount_cents) }
      exact_weights.sum.zero? ? booked_weights : exact_weights
    end

    def fee_taxes_by_key
      @fee_taxes_by_key ||= invoice.fees.order(:created_at, :id).includes(:applied_taxes)
        .flat_map(&:applied_taxes).group_by do |fee_tax|
          invoice_applied_tax = resolve_invoice_applied_tax(fee_tax)
          tax_key(invoice_applied_tax) if invoice_applied_tax
        end
    end

    # NOTE: indexes the credit note items by the invoice applied tax their fee taxes resolve to,
    #       keyed by that invoice tax's code and rate. Keying on the resolved invoice tax, not on
    #       the fee tax, lets two fee taxes that resolve to the same invoice tax share a single
    #       credit note tax instead of colliding on the (credit_note_id, tax_code, tax_rate) index.
    #       An item is listed once per fee tax, not once per key: a fee can carry several provider
    #       components with the same code and rate (e.g. state and county, both "Tax" at 5%), and
    #       each one must be credited, as it was taxed.
    #       Returns nil, with the failure recorded on the result, when a fee tax cannot be resolved.
    #       Example output: { ["vat", 20.0] => { invoice_applied_tax: tax, items: [item1, item2] } }
    def index_items_by_invoice_tax
      items.each_with_object({}) do |item, index|
        item.fee.applied_taxes.each do |fee_applied_tax|
          invoice_applied_tax = find_invoice_applied_tax(fee_applied_tax)
          return nil unless invoice_applied_tax

          entry = index[tax_key(invoice_applied_tax)] ||= {invoice_applied_tax:, items: []}
          entry[:items] << item
        end
      end
    end

    def items_amount_cents
      @items_amount_cents ||= items.sum(&:precise_amount_cents)
    end

    def coupons_adjustment_amount_cents
      return 0 if invoice.version_number < Invoice::COUPON_BEFORE_VAT_VERSION

      items.sum { |item| prorated_coupon_amount_cents(item) }
    end

    def prorated_coupon_amount_cents(item)
      item_fee_rate = item.fee.amount_cents.zero? ? 0 : item.precise_amount_cents.fdiv(item.fee.amount_cents)
      item.fee.precise_coupons_amount_cents * item_fee_rate
    end

    def base_amounts
      @base_amounts ||= indexed_items.transform_values do |entry|
        entry[:items].sum do |item|
          item.precise_amount_cents - prorated_coupon_amount_cents(item)
        end
      end
    end

    # NOTE: Tax might not be applied to all items of the credit note.
    #       In order to compute the credit_note#taxes_rate, we have to apply
    #       a pro-rata of the items attached to the tax on the total items amount
    def pro_rated_taxes_rate(applied_tax)
      tax_items_amount_cents = base_amounts.fetch(tax_key(applied_tax))
      total_items_amount_cents = items_amount_cents - result.coupons_adjustment_amount_cents

      items_rate = total_items_amount_cents.zero? ? 0 : tax_items_amount_cents.fdiv(total_items_amount_cents)

      items_rate * applied_tax.tax_rate
    end

    # NOTE: a fee tax resolves to the invoice tax with the same code and rate. When no invoice tax
    #       has that rate (the fee and the invoice were taxed at different rates, e.g. the tax rate
    #       changed in between), it falls back to the invoice tax carrying the same code, but only
    #       if exactly one does: several invoice taxes sharing a code is the provider multi-rate
    #       case, where the rate is the only thing telling them apart.
    def resolve_invoice_applied_tax(fee_applied_tax)
      key = tax_key(fee_applied_tax)
      exact_match = invoice_applied_taxes.find { |applied_tax| tax_key(applied_tax) == key }
      return exact_match if exact_match

      code_matches = invoice_applied_taxes.select { |applied_tax| applied_tax.tax_code == fee_applied_tax.tax_code }
      code_matches.first if code_matches.one?
    end

    def find_invoice_applied_tax(fee_applied_tax)
      invoice_applied_tax = resolve_invoice_applied_tax(fee_applied_tax)
      return invoice_applied_tax if invoice_applied_tax

      result.service_failure!(
        code: "invoice_applied_tax_not_found",
        message: "Invoice #{invoice.id} has no applied tax matching #{tax_key(fee_applied_tax).join(", ")}"
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
