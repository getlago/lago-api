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

      amount_cents = credit_note.items.sum(:amount_cents)
      credit_amount_cents = (amount_cents + (amount_cents * fee.vat_rate).fdiv(100)).round
      return result if credit_amount_cents == credit_note.credit_amount_cents

      credit_note.update!(
        vat_amount_cents: credit_note.items.sum { |i| i.amount_cents * i.fee.vat_rate }.fdiv(100).round,
        credit_amount_cents:,
        balance_amount_cents: credit_amount_cents,
        total_amount_cents: credit_amount_cents + credit_note.refund_amount_cents,
      )
      result
    end

    private

    attr_accessor :credit_note, :fee
  end
end
