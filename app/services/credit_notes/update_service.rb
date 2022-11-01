# frozen_string_literal: true

module CreditNotes
  class UpdateService < BaseService
    def initialize(credit_note:, **params)
      @credit_note = credit_note
      @params = params&.with_indifferent_access

      super
    end

    def call
      return result.not_found_failure!(resource: 'credit_note') if credit_note.nil?

      credit_note.refund_status = params[:refund_status] if params.key?(:refund_status)
      credit_note.save!

      result.credit_note = credit_note

      result
    rescue ArgumentError
      result.single_validation_failure!(field: :refund_status, error_code: 'value_is_invalid')
    end

    private

    attr_reader :credit_note, :params
  end
end
