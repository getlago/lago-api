# frozen_string_literal: true

module CreditNotes
  class ValidateItemService < BaseValidator
    def valid?
      return false unless valid_fee?

      valid_individual_amount?
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

    def credited_invoice_amount_cents
      invoice.credit_notes.sum(:amount_cents)
    end

    def valid_fee?
      return true if item.fee.present?

      result.not_found_failure!(resource: 'fee')

      false
    end

    # NOTE: Check if item credit amount is less than or equal to fee remaining creditable amount
    def valid_individual_amount?
      return true if match_fee_amount?

      add_error(field: :credit_amount_cents, error_code: 'higher_than_remaining_fee_amount')
    end

    def match_fee_amount?
      item.credit_amount_cents.positive? &&
        item.credit_amount_cents <= fee.amount_cents - credited_fee_amount_cents
    end

    # NOTE: Check if item credit amount is less than or equal to invoice remaining creditable amount
    def valid_global_amount?
      return true if item.credit_amount_cents <= invoice.fee_total_amount_cents - credited_invoice_amount_cents

      add_error(field: :credit_amount_cents, error_code: 'higher_than_remaining_invoice_amount')
    end
  end
end
