# frozen_string_literal: true

module CreditNotes
  class RefreshDraftService < BaseService
    def initialize(credit_note:, fee:)
      @credit_note = credit_note
      @fee = fee

      super
    end

    def call
      result.credit_note = credit_note
      return result unless credit_note.draft?

      credit_note.items.update_all(fee_id: fee.id) # rubocop:disable Rails/SkipsModelValidations

      amount_result = CreditNotes::ComputeAmountService.call(
        invoice: fee.invoice,
        items: credit_note.items,
      )

      credit_note.precise_coupons_adjustment_amount_cents = amount_result.coupons_adjustment_amount_cents
      credit_note.coupons_adjustment_amount_cents = amount_result.coupons_adjustment_amount_cents.round
      credit_note.precise_taxes_amount_cents = amount_result.taxes_amount_cents
      credit_note.taxes_amount_cents = amount_result.taxes_amount_cents.round

      credit_note.credit_amount_cents = (
        credit_note.items.sum(:precise_amount_cents).truncate(CreditNote::DB_PRECISION_SCALE) -
        amount_result.coupons_adjustment_amount_cents +
        amount_result.taxes_amount_cents
      ).round

      credit_note.balance_amount_cents = credit_note.credit_amount_cents
      credit_note.total_amount_cents = credit_note.credit_amount_cents + credit_note.refund_amount_cents

      credit_note.save!

      result
    end

    private

    attr_accessor :credit_note, :fee
  end
end
