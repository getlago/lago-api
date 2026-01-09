# frozen_string_literal: true

module Credits
  class AppliedAfterFinalizationService < BaseService
    def initialize(credit_note: )
      @credit_note = credit_note

      super(nil)
    end

    def call

      # NOTE: create a new credit line on the invoice
      credit = Credit.new(
        organization_id: invoice.organization_id,
        invoice: credit_note.invoice,
        credit_note:,
        amount_cents: credit_note.applied_to_source_invoice_amount_cents,
        apply_after_finalization: true,
        amount_currency: invoice.currency,
        before_taxes: false
      )
      credit.save!

      ## check invoice total due amount and update invoice payment status
      ## if invoice total due amount is 0, update invoice payment status to paid
      ## if invoice type credit terminate wallet transaction

    end

    private

    attr_accessor :credit_note
  end
end