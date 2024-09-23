# frozen_string_literal: true

module Invoices
  class NumberGenerationService < BaseService
    def initialize(invoice:)
      @invoice = invoice

      super
    end

    def call
      unless invoice.finalized?
        # For invoice that is not finalized we just want to assign draft invoice number
        invoice.ensure_number
        invoice.save!

        return result
      end

      invoice.ensure_invoice_sequential_id
      if invoice.organization.per_organization?
        invoice.ensure_organization_sequential_id
      end

      invoice.ensure_number
      invoice.save!

      result.invoice = invoice

      result
    end

    private

    attr_reader :invoice
  end
end
