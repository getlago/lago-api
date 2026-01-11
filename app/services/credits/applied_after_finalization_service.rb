# frozen_string_literal: true

module Credits
  class AppliedAfterFinalizationService < BaseService
    def initialize(credit_note:)
      @credit_note = credit_note
      @invoice = credit_note.invoice

      super(nil)
    end

    def call
      ActiveRecord::Base.transaction do
        credit = Credit.new(
          organization_id: invoice.organization_id,
          invoice: invoice,
          credit_note:,
          amount_cents: credit_note.applied_to_source_invoice_amount_cents,
          apply_after_finalization: true,
          amount_currency: invoice.currency,
          before_taxes: false
        )
        credit.save!

        mark_invoice_as_paid if invoice_fully_covered?

        result.credit = credit
        result
      end
    end

    private

    attr_accessor :credit_note, :invoice

    def invoice_fully_covered?
      invoice.total_due_amount_cents <= 0
    end

    def mark_invoice_as_paid
      Invoices::UpdateService.call(
        invoice: invoice,
        params: {
          payment_status: :succeeded,
        },
        webhook_notification: true
      )
    end
  end
end