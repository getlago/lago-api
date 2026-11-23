# frozen_string_literal: true

module Invoices
  class FinalizeAndPublishAdvanceChargesService < BaseService
    Result = BaseResult

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result unless invoice.advance_charges?

      if invoice.generating?
        Invoices::TransitionToFinalStatusService.call!(invoice:)
        invoice.save! if invoice.changed?
      end

      return result if invoice.closed?

      SendWebhookJob.perform_later("invoice.created", invoice)
      Utils::ActivityLog.produce(invoice, "invoice.created")
      Invoices::RecordAdvanceChargesPaymentService.call!(invoice:)
      Invoices::GenerateDocumentsJob.perform_later(invoice:, notify: false)
      Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
      Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_later(invoice:) if invoice.should_sync_hubspot_invoice?

      result
    end

    private

    attr_reader :invoice
  end
end
