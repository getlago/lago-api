# frozen_string_literal: true

module Invoices
  class DeleteService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:)
      @invoice = invoice

      super
    end

    activity_loggable(
      action: "invoice.deleted",
      record: -> { invoice }
    )

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice

      invoice.with_lock do
        return result.not_allowed_failure!(code: "not_deletable") unless invoice.draft?
        return result.not_allowed_failure!(code: "invoice_synced_to_external_system") if synced_externally?

        soft_delete_credit_notes!

        invoice.mark_as_deleted!
      end

      return result unless result.success?

      result.invoice = invoice
      SendWebhookJob.perform_later("invoice.deleted", result.invoice)

      result
    rescue AASM::InvalidTransition
      result.not_allowed_failure!(code: "not_deletable")
    end

    private

    attr_reader :invoice

    def soft_delete_credit_notes!
      invoice.credit_notes.not_deleted.find_each do |credit_note|
        delete_result = CreditNotes::DeleteService.call(credit_note:)
        next if delete_result.success?

        result.not_allowed_failure!(code: "credit_note_not_deletable")
        raise ActiveRecord::Rollback
      end
    end

    def synced_externally?
      invoice.integration_resources.exists?
    end
  end
end
