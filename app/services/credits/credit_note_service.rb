# frozen_string_literal: true

module Credits
  class CreditNoteService < BaseService
    def initialize(invoice:, credit_notes:)
      @invoice = invoice
      @credit_notes = credit_notes

      super(nil)
    end

    def call
      return result if already_applied?

      result.credits = []
      remaining_invoice_amount = invoice.total_amount_cents

      ActiveRecord::Base.transaction do
        credit_notes.each do |credit_note|
          credit_amount = compute_credit_amount(credit_note, remaining_invoice_amount)
          next unless credit_amount.positive?

          # NOTE: create a new credit line on the invoice
          credit = Credit.create!(
            invoice: invoice,
            credit_note: credit_note,
            amount_cents: credit_amount,
            amount_currency: invoice.currency,
          )

          # NOTE: Consume remaining credit on the credit note
          update_remaining_credit(credit_note, credit_amount)
          remaining_invoice_amount -= credit_amount

          result.credits << credit

          # NOTE: Invoice amount is fully covered by the credit notes
          break if remaining_invoice_amount.zero?
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice, :credit_notes

    delegate :customer, to: :invoice

    def already_applied?
      invoice.credits.where.not(credit_note_id: nil).exists?
    end

    def compute_credit_amount(credit_note, remaining_invoice_amount)
      if credit_note.balance_amount_cents > remaining_invoice_amount
        remaining_invoice_amount
      else
        credit_note.balance_amount_cents
      end
    end

    def update_remaining_credit(credit_note, consumed_credit)
      credit_note.update!(
        balance_amount_cents: credit_note.balance_amount_cents - consumed_credit,
      )

      credit_note.consumed! if credit_note.balance_amount_cents.zero?
    end
  end
end
