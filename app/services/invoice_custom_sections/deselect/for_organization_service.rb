# frozen_string_literal: true

module InvoiceCustomSections
  module Deselect
    class ForOrganizationService < BaseService
      def initialize(section:)
        @section = section
        @organization = section.organization
        super
      end

      def call
        deselect_for_organization
        result
      end

      private

      attr_reader :section, :organization

      def deselect_for_organization
        return unless organization.selected_invoice_custom_sections.include?(section)

        InvoiceCustomSectionSelection.where(
          organization_id: organization.id, invoice_custom_section_id: section.id
        ).destroy_all
        result.section = section
      end
    end
  end
end
