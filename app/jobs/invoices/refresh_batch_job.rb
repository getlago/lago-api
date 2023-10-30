# frozen_string_literal: true

module Invoices
  class RefreshBatchJob < ApplicationJob
    queue_as 'invoices'

    def perform(invoice_ids)
      refresh_service = refresh_invoices_service(invoice_ids)
      return unless refresh_service.draft_invoices_refresh_enabled?

      refresh_service.disable_draft_invoices_refresh!

      Invoice.find(invoice_ids).each do |invoice|
        ::Invoices::RefreshDraftService.call(invoice:)
      end

      refresh_service.enable_draft_invoices_refresh!
    end

    private

    def refresh_invoices_service(invoice_ids)
      invoice = Invoice.find(invoice_ids.first)

      ::Invoices::RefreshDraftService.new(invoice:)
    end
  end
end
