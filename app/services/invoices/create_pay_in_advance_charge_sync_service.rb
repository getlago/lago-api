# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceChargeSyncService < CreatePayInAdvanceChargeService
    def call
      fees = generate_fees
      return Result.new if fees.none?

      create_generating_invoice unless invoice
      result.invoice = invoice

      ActiveRecord::Base.transaction do
        fees.each { |f| f.update!(invoice:) }

        invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
        invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents
        Credits::AppliedCouponsService.call(invoice:) if invoice.fees_amount_cents&.positive?

        Invoices::ComputeAmountsFromFees.call(invoice:)
        create_credit_note_credit if credit_notes.any?
        create_applied_prepaid_credit if should_create_applied_prepaid_credit?

        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        invoice.finalized!
      end

      track_invoice_created(invoice)

      deliver_webhooks if should_deliver_webhook?
      InvoiceMailer.with(invoice:).finalized.deliver_later if should_deliver_email?
      Invoices::Payments::CreateSyncService.new(invoice).call

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue Sequenced::SequenceError
      raise
    rescue StandardError => e
      result.fail_with_error!(e)
    end
  end
end