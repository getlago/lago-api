# frozen_string_literal: true

module CreditNotes
  class EstimateService < BaseService
    def initialize(invoice:, items:)
      @invoice = invoice
      @items = items

      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') unless invoice
      return result.forbidden_failure! unless License.premium?
      return result.not_allowed_failure!(code: 'invalid_type_or_status') unless valid_type_or_status?

      credit_note = CreditNote.new(
        customer: invoice.customer,
        invoice:,
        total_amount_currency: invoice.currency,
        vat_amount_currency: invoice.currency,
        credit_amount_currency: invoice.currency,
        refund_amount_currency: invoice.currency,
        balance_amount_currency: invoice.currency,
      )

      validate_items
      return result unless result.success?

      compute_amounts_and_taxes

      # TODO: assign creditable and refundable attribute and return them in a serializer
      credit_note.credit_amount_cents = 0
      credit_note.refund_amount_cents = 0

      result.credit_note = credit_note
      result
    end

    private

    attr_reader :invoice

    delegate :credit_note, to: :result

    def valid_type_or_status?
      return false if invoice.credit?

      invoice.version_number >= Invoice::CREDIT_NOTES_MIN_VERSION
    end

    def validate_items
      items.each do |item_attr|
        amount_cents = item_attr[:amount_cents] || 0

        item = credit_note.items.new(
          fee: invoice.fees.find_by(id: item_attr[:fee_id]),
          amount_cents: amount_cents.round,
          precise_amount_cents: amount_cents,
          amount_currency: invoice.currency,
        )
        break unless valid_item?(item)
      end
    end

    def valid_item?(item)
      CreditNote::ValidateItemService.new(result, item:).valid?
    end

    def compute_amounts_and_taxes
      taxes_result = CreditNotes::ApplyTaxesService.call(
        invoice:,
        items: credit_note.items,
      )

      credit_note.precise_coupons_adjustment_amount_cents = taxes_result.coupons_adjustment_amount_cents
      credit_note.coupons_adjustment_amount_cents = taxes_result.coupons_adjustment_amount_cents.round
      credit_note.precise_taxes_amount_cents = taxes_result.taxes_amount_cents
      credit_note.taxes_amount_cents = taxes_result.taxes_amount_cents.round
      credit_note.taxes_rate = taxes_result.taxes_rate

      taxes_result.applied_taxes.each { |applied_tax| credit_note.applied_taxes << applied_tax }
    end
  end
end
