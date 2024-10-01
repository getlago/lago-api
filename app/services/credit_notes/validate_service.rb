# frozen_string_literal: true

module CreditNotes
  class ValidateService < BaseValidator
    def valid?
      valid_invoice_status?
      valid_items_amount?
      valid_refund_amount?
      valid_credit_amount?
      valid_global_amount?

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    def credit_note
      args[:item]
    end

    delegate :invoice, to: :credit_note

    def total_amount_cents
      credit_note.credit_amount_cents + credit_note.refund_amount_cents
    end

    def refunded_invoice_amount_cents
      invoice.credit_notes.finalized.where.not(id: credit_note.id).sum(:refund_amount_cents)
    end

    def credited_invoice_amount_cents
      invoice.credit_notes.finalized.where.not(id: credit_note.id).sum(:credit_amount_cents)
    end

    def invoice_credit_note_total_amount_cents
      credited_invoice_amount_cents + refunded_invoice_amount_cents
    end

    def total_items_amount_cents
      (
        credit_note.items.sum(&:precise_amount_cents) -
        credit_note.precise_coupons_adjustment_amount_cents +
        credit_note.precise_taxes_amount_cents
      ).round
    end

    def valid_invoice_status?
      if credit_note.refund_amount_cents.positive?
        return true if invoice.payment_succeeded?

        add_error(field: :refund_amount_cents, error_code: 'cannot_refund_unpaid_invoice')
        return false
      end

      true
    end

    def valid_invoice_type?
      return unless invoice.credit?

      add_error(field: :base, error_code: 'cannot_credit_invoice')
      false
    end

    # NOTE: Check if total amount matched the items amount
    def valid_items_amount?
      return true if total_amount_cents == total_items_amount_cents

      add_error(field: :base, error_code: 'does_not_match_item_amounts')
    end

    # NOTE: Check if refunded amount is less than or equal to invoice total amount
    def valid_refund_amount?
      return true if credit_note.refund_amount_cents <= invoice.total_amount_cents - refunded_invoice_amount_cents

      add_error(field: :refund_amount_cents, error_code: 'higher_than_remaining_invoice_amount')
    end

    # NOTE: Check if credited amount is less than or equal to invoice fee amount
    def valid_credit_amount?
      return true if credit_note.credit_amount_cents <= invoice.fee_total_amount_cents - credited_invoice_amount_cents

      add_error(field: :credit_amount_cents, error_code: 'higher_than_remaining_invoice_amount')
    end

    # NOTE: Check if total amount is less than or equal to invoice fee amount
    def valid_global_amount?
      return true if total_amount_cents <= invoice.fee_total_amount_cents - invoice_credit_note_total_amount_cents

      add_error(field: :base, error_code: 'higher_than_remaining_invoice_amount')
    end
  end
end
