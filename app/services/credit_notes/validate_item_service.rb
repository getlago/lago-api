# frozen_string_literal: true

module CreditNotes
  class ValidateItemService < BaseValidator
    def valid?
      return false unless valid_fee?

      valid_invoice_status?

      valid_individual_credit_amount?
      valid_individual_refund_amount?
      valid_individual_amount?
      valid_global_credit_amount?
      valid_global_refund_amount?
      valid_global_amount?

      if errors?
        result.validation_failure!(errors: errors)
        return false
      end

      true
    end

    private

    def item
      args[:item]
    end

    delegate :credit_note, :fee, to: :item
    delegate :invoice, to: :credit_note

    def credited_fee_amount_cents
      fee.credit_note_items.sum(:credit_amount_cents)
    end

    def refunded_fee_amount_cents
      fee.credit_note_items.sum(:refund_amount_cents)
    end

    def total_fee_amount_cents
      credited_fee_amount_cents + refunded_fee_amount_cents
    end

    def credited_invoice_amount_cents
      invoice.credit_notes.sum(:credit_amount_cents)
    end

    def refunded_invoice_amount_cents
      invoice.credit_notes.sum(:refund_amount_cents)
    end

    def invoice_credit_note_total_amount_cents
      credited_invoice_amount_cents + refunded_invoice_amount_cents
    end

    def valid_fee?
      return true if item.fee.present?

      result.not_found_failure!(resource: 'fee')

      false
    end

    def valid_invoice_status?
      if item.refund_amount_cents.positive?
        return true if invoice.succeeded?

        add_error(field: :refund_amount_cents, error_code: 'cannot_refund_unpaid_invoice')
        return false
      end

      true
    end

    # NOTE: Check if item credit amount is less than or equal to fee remaining creditable amount
    def valid_individual_credit_amount?
      return true if item.credit_amount_cents.zero?
      return true if credit_match_fee_amount?

      add_error(field: :credit_amount_cents, error_code: 'higher_than_remaining_fee_amount')
    end

    def credit_match_fee_amount?
      item.credit_amount_cents.positive? &&
        item.credit_amount_cents <= fee.total_amount_cents - credited_fee_amount_cents
    end

    # NOTE: Check if refund amount is less than or equal to fee remaining refundable amount
    def valid_individual_refund_amount?
      return true if item.refund_amount_cents.zero?
      return true if refund_match_fee_amount?

      add_error(field: :refund_amount_cents, error_code: 'higher_than_remaining_fee_amount')
    end

    def refund_match_fee_amount?
      item.refund_amount_cents.positive? &&
        item.refund_amount_cents <= fee.total_amount_cents - refunded_fee_amount_cents
    end

    # NOTE: Check if total credit note amount is less than or equal to fee remaining amount
    def valid_individual_amount?
      return true if item.total_amount_cents <= fee.total_amount_cents - total_fee_amount_cents

      add_error(field: :base, error_code: 'higher_than_remaining_fee_amount')
    end

    # NOTE: Check if item credit amount is less than or equal to invoice remaining creditable amount
    def valid_global_credit_amount?
      return true if item.credit_amount_cents <= invoice.fee_total_amount_cents - credited_invoice_amount_cents

      add_error(field: :credit_amount_cents, error_code: 'higher_than_remaining_invoice_amount')
    end

    # NOTE: Check if item refund amount is less than or equal to invoice remaining refundable amount
    def valid_global_refund_amount?
      return true if item.refund_amount_cents <= invoice.total_amount_cents - refunded_invoice_amount_cents

      add_error(field: :refund_amount_cents, error_code: 'higher_than_remaining_invoice_amount')
    end

    # NOTE: Check if item credit note amount is less than or equal to invoice fee amount
    def valid_global_amount?
      return true if item.total_amount_cents <= invoice.amount_cents - invoice_credit_note_total_amount_cents

      add_error(field: :base, error_code: 'higher_than_remaining_invoice_amount')
    end
  end
end
