# frozen_string_literal: true

module Invoices
  class FinalizeContractInvoiceService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      result.invoice = invoice
      return result unless invoice.contract? && (invoice.generating? || invoice.draft?)

      ActiveRecord::Base.transaction do
        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        Invoices::TransitionToFinalStatusService.call!(invoice:)
        invoice.save!
      end

      publish unless invoice.closed?

      result
    end

    private

    attr_reader :invoice

    def publish
      SendWebhookJob.perform_later("invoice.created", invoice)
      Utils::ActivityLog.produce(invoice, "invoice.created")
      Invoices::GenerateDocumentsJob.perform_later(invoice:, notify: should_deliver_email?)
      Invoices::Payments::CreateService.call_async(invoice:)
      Utils::SegmentTrack.invoice_created(invoice)
    end

    def should_deliver_email?
      License.premium? && invoice.billing_entity.email_settings.include?("invoice.finalized")
    end
  end
end
