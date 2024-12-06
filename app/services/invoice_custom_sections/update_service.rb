# frozen_string_literal: true

module InvoiceCustomSections
  class UpdateService < BaseService
    def initialize(invoice_custom_section:, update_params:, selected: false)
      @update_params = update_params
      @invoice_custom_section = invoice_custom_section
      @selected = selected
      super
    end

    def call
      invoice_custom_section.update!(update_params)
      if selected
        SelectService.call(section: invoice_custom_section, organization: invoice_custom_section.organization)
      else
        DeselectService.call(section: invoice_custom_section, organization: invoice_custom_section.organization)
      end
      result.invoice_custom_section = invoice_custom_section
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice_custom_section, :update_params, :selected
  end
end
