# frozen_string_literal: true

module InvoiceCustomSections
  class DeselectService < BaseService
    def initialize(section:, organization:)
      @section = section
      @organization = organization
      super
    end

    def call
      deselect_for_organization if organization
      result
    end

    private

    attr_reader :section, :organization

    def deselect_for_organization
      return unless organization.selected_invoice_custom_sections.include?(section)

      InvoiceCustomSectionSelection.where(
        organization_id: organization.id, invoice_custom_section_id: section.id
      ).destroy_all
      result.organization = organization
    end
  end
end
