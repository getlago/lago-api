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

      # requires_new adds a savepoint so a rollback only impacts this block, not any outer transaction
      invoice.with_lock(requires_new: true) do
        return result.not_allowed_failure!(code: "not_deletable") unless invoice.draft?
        return result.not_allowed_failure!(code: "invoice_synced_to_external_system") if synced_externally?

        mark_credit_notes_as_deleted!

        invoice.mark_as_deleted!
      end

      return result unless result.success?

      result.invoice = invoice
      SendWebhookJob.perform_later("invoice.deleted", result.invoice)

      result
    end

    private

    attr_reader :invoice

    def mark_credit_notes_as_deleted!
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
