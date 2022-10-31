# frozen_string_literal: true

module CreditNotes
  class VoidService < BaseService
    def initialize(credit_note:)
      @credit_note = credit_note

      super
    end

    def call
      return result.not_found_failure!(resource: 'credit_note') if credit_note.nil?

      result.credit_note = credit_note
      return result.not_allowed_failure!(code: 'no_voidable_amount') unless credit_note.voidable?

      credit_note.update!(
        credit_status: :voided,
        voided_at: Time.current,
      )

      result
    end

    private

    attr_reader :credit_note
  end
end
