# frozen_string_literal: true

module CreditNotes
  class DeleteService < BaseService
    Result = BaseResult[:credit_note]

    def initialize(credit_note:)
      @credit_note = credit_note

      super
    end

    def call
      return result.not_found_failure!(resource: "credit_note") unless credit_note
      return result.not_allowed_failure!(code: "not_deletable") unless credit_note.draft?

      credit_note.deleted!

      result.credit_note = credit_note
      result
    end

    private

    attr_reader :credit_note
  end
end
