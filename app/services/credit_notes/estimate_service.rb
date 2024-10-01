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

      @credit_note = CreditNote.new(
        customer: invoice.customer,
        invoice:,
        total_amount_currency: invoice.currency,
        credit_amount_currency: invoice.currency,
        refund_amount_currency: invoice.currency,
        balance_amount_currency: invoice.currency
      )

      validate_items
      return result unless result.success?

      compute_amounts_and_taxes

      result.credit_note = credit_note
      result
    end

    private

    attr_reader :invoice, :items, :credit_note

    def valid_type_or_status?
      return false if invoice.credit?

      invoice.version_number >= Invoice::CREDIT_NOTES_MIN_VERSION
    end

    def validate_items
      items.each do |item_attr|
        amount_cents = item_attr[:amount_cents]&.to_i || 0

        item = CreditNoteItem.new(
          fee: invoice.fees.find_by(id: item_attr[:fee_id]),
          amount_cents: amount_cents.round,
          precise_amount_cents: amount_cents,
          amount_currency: invoice.currency
        )
        credit_note.items << item

        break unless valid_item?(item)
      end
    end

    def valid_credit_note?
      CreditNotes::ValidateService.new(result, item: credit_note).valid?
    end

    def valid_item?(item)
      CreditNotes::ValidateItemService.new(result, item:).valid?
    end

    def compute_amounts_and_taxes
      taxes_result = CreditNotes::ApplyTaxesService.call(
        invoice:,
        items: credit_note.items
      )

      credit_note.precise_coupons_adjustment_amount_cents = taxes_result.coupons_adjustment_amount_cents
      credit_note.coupons_adjustment_amount_cents = taxes_result.coupons_adjustment_amount_cents.round
      credit_note.precise_taxes_amount_cents = taxes_result.taxes_amount_cents
      adjust_credit_note_tax_precise_rounding if credit_note_for_all_remaining_amount?

      credit_note.taxes_amount_cents = credit_note.precise_taxes_amount_cents.round
      credit_note.taxes_rate = taxes_result.taxes_rate

      taxes_result.applied_taxes.each { |applied_tax| credit_note.applied_taxes << applied_tax }

      credit_note.credit_amount_cents = (
        credit_note.items.sum(&:amount_cents) -
        taxes_result.coupons_adjustment_amount_cents +
        credit_note.precise_taxes_amount_cents
      ).round

      compute_refundable_amount
      credit_note.total_amount_cents = credit_note.credit_amount_cents
    end

    def credit_note_for_all_remaining_amount?
      credit_note.items.sum(&:precise_amount_cents) == credit_note.invoice.fees.sum(&:creditable_amount_cents)
    end

    def adjust_credit_note_tax_precise_rounding
      credit_note.precise_taxes_amount_cents -= all_rounding_tax_adjustments
    end

    def all_rounding_tax_adjustments
      credit_note.invoice.credit_notes.sum(&:taxes_rounding_adjustment)
    end

    def compute_refundable_amount
      credit_note.refund_amount_cents = credit_note.credit_amount_cents

      # invoice.refundable_amount_cents is incorrect - in our case it returns 8200, but it should be 8199...
      refundable_amount_cents = invoice.refundable_amount_cents
      return unless credit_note.credit_amount_cents > refundable_amount_cents

      credit_note.refund_amount_cents = refundable_amount_cents
    end
  end
end
