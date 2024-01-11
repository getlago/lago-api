# frozen_string_literal: true

module Invoices
  class SubscriptionSyncService < SubscriptionService
    def call
      return result if active_subscriptions.empty? && recurring

      create_generating_invoice unless invoice
      result.invoice = invoice

      ActiveRecord::Base.transaction do
        invoice.status = invoice_status
        invoice.save!

        fee_result = Invoices::CalculateFeesService.call(
          invoice:,
          recurring:,
        )

        fee_result.raise_if_error!
        invoice.reload
      end

      if grace_period?
        SendWebhookJob.perform_later('invoice.drafted', invoice) if should_deliver_webhook?
      else
        SendWebhookJob.perform_later('invoice.created', invoice) if should_deliver_webhook?
        InvoiceMailer.with(invoice:).finalized.deliver_later if should_deliver_finalized_email?
        Invoices::Payments::CreateSyncService.new(invoice).call
        track_invoice_created(invoice)
      end

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