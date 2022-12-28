# frozen_string_literal: true

module Invoices
  class FinalizeService < BaseService
    def self.call(...)
      new(...).call
    end

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') if invoice.nil?

      ActiveRecord::Base.transaction do
        result = Invoices::RefreshDraftService.call(invoice:)
        result.raise_if_error!

        invoice.update!(status: :finalized, issuing_date:)
        SendWebhookJob.perform_later(:invoice, invoice) if invoice.organization.webhook_url?
        Invoices::Payments::CreateService.new(invoice).call
        track_invoice_created(invoice)

        result
      end
    end

    private

    attr_accessor :invoice

    def issuing_date
      @issuing_date ||= Time.current.in_time_zone(invoice.customer.applicable_timezone).to_date
    end

    def track_invoice_created(invoice)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type,
        },
      )
    end
  end
end
