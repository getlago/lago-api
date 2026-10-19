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
      return result unless finalizable?

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

    def finalizable?
      invoice.contract? && invoice.generating?
    end

    def publish
      SendWebhookJob.perform_after_commit("invoice.created", invoice)
      Utils::ActivityLog.produce_after_commit(invoice, "invoice.created")
      Invoices::GenerateDocumentsJob.perform_after_commit(invoice:, notify: should_deliver_email?)
      Invoices::Payments::CreateService.call_async(invoice:)
      Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_after_commit(invoice:) if invoice.should_sync_hubspot_invoice?
      after_commit { Utils::SegmentTrack.invoice_created(invoice) }
    end

    def should_deliver_email?
      License.premium? && invoice.billing_entity.email_settings.include?("invoice.finalized")
    end
  end
end
