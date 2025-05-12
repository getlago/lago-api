# frozen_string_literal: true

module Invoices
  class ApplyInvoiceCustomSectionsService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      @customer = invoice.customer

      super()
    end

    def call
      result.applied_sections = []
      return result if customer.skip_invoice_custom_sections

      customer.applicable_invoice_custom_sections.each do |custom_section|
        invoice.applied_invoice_custom_sections.create!(
          organization_id: invoice.organization_id,
          code: custom_section.code,
          details: custom_section.details,
          display_name: custom_section.display_name,
          name: custom_section.name
        )
      end
      result.applied_sections = invoice.applied_invoice_custom_sections
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice, :customer
  end
end
