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
      create_manual_payment
      Invoices::GenerateDocumentsJob.perform_later(invoice:, notify: false)
      Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
      Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_later(invoice:) if invoice.should_sync_hubspot_invoice?
      Utils::SegmentTrack.invoice_created(invoice)

      result
    end

    private

    attr_reader :invoice

    def create_manual_payment
      params = {
        invoice_id: invoice.id,
        amount_cents: invoice.total_amount_cents,
        reference: I18n.t("invoice.charges_paid_in_advance"),
        created_at: invoice.created_at
      }

      ::Payments::ManualCreateJob.perform_later(organization: invoice.organization, params:)
    end
  end
end
