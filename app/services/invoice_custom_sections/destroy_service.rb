# frozen_string_literal: true

module InvoiceCustomSections
  class DestroyService < BaseService
    def initialize(invoice_custom_section:)
      @invoice_custom_section = invoice_custom_section
      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice_custom_section') unless invoice_custom_section

      ActiveRecord::Base.transaction do
        invoice_custom_section.discard
        Deselect::ForAllUsagesService.call(section: invoice_custom_section).raise_if_error!
        result.invoice_custom_section = invoice_custom_section
        result
      end
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice_custom_section
  end
end
