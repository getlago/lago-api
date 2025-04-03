# frozen_string_literal: true

module InvoiceCustomSections
  class CreateService < BaseService
    def initialize(organization:, create_params:, selected: false, system_generated: false)
      @organization = organization
      @create_params = create_params
      @selected = selected
      @system_generated = system_generated
      super
    end

    def call
      attrs = create_params.merge(section_type: section_type_value)
      invoice_custom_section = organization.invoice_custom_sections.create!(attrs)
      Organizations::SelectInvoiceCustomSectionService.call(section: invoice_custom_section) if selected
      result.invoice_custom_section = invoice_custom_section
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :create_params, :selected, :system_generated

    def section_type_value
      system_generated ? :system_generated : :manual
    end
  end
end