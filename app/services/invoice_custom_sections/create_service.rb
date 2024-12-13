# frozen_string_literal: true

module InvoiceCustomSections
  class CreateService < BaseService
    def initialize(organization:, create_params:, selected: false)
      @organization = organization
      @create_params = create_params
      @selected = selected
      super
    end

    def call
      invoice_custom_section = organization.invoice_custom_sections.create!(create_params)
      Organizations::SelectInvoiceCustomSectionService.call(organization:, section: invoice_custom_section) if selected
      result.invoice_custom_section = invoice_custom_section
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :create_params, :selected
  end
end
