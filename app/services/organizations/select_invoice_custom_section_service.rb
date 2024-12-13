# frozen_string_literal: true

module Organizations
  class SelectInvoiceCustomSectionService < BaseService
    def initialize(organization:, section:)
      @section = section
      @organization = organization
      super
    end

    def call
      select_for_organization
      result
    end

    private

    attr_reader :section, :organization

    def select_for_organization
      return if organization.selected_invoice_custom_sections.include?(section)

      organization.selected_invoice_custom_sections << section
      result.organization = organization
    end
  end
end
