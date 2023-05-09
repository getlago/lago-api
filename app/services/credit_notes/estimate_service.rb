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
      return result.forbidden_failure! unless should_create_credit_note?
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

      credit_note.precise_coupons_adjustment_amount_cents = coupons_adjustment_amount_cents
      credit_note.coupons_adjustment_amount_cents = credit_note.precise_coupons_adjustment_amount_cents.round
      credit_note.precise_vat_amount_cents = vat_amount_cents
      credit_note.vat_amount_cents = credit_note.precise_vat_amount_cents.round

      # TODO: assign creditable and refundable attribute and return them in a serializer

      result.credit_note = credit_note
      result
    end

    private

    attr_reader :invoice

    delegate :credit_note, to: :result

    def should_create_credit_note?
      # NOTE: credit note is a premium feature
      License.premium?
    end

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

    def coupons_adjustment_amount_cents
      return 0 if invoice.version_number < Invoice::COUPON_BEFORE_VAT_VERSION

      invoice.coupons_amount_cents.fdiv(invoice.fees_amount_cents) * credit_note.items.sum(&:precise_amount_cents)
    end

    def vat_amount_cents
      credit_note.items.sum do |item|
        # NOTE: Because coupons are applied before VAT,
        #       we have to discribute the coupon adjustement at prorata of each items
        #       to compute the VAT
        item_rate = item.precise_amount_cents.fdiv(credit_note.items.sum(&:precise_amount_cents))
        prorated_coupon_amount = credit_note.precise_coupons_adjustment_amount_cents * item_rate
        (item.precise_amount_cents - prorated_coupon_amount) * (item.fee.vat_rate || 0)
      end.fdiv(100)
    end
  end
end
