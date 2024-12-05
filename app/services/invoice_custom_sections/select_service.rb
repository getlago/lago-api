# frozen_string_literal: true

module InvoiceCustomSections
  class SelectService < BaseService
    def initialize(section:, organization:)
      @section = section
      @organization = organization
      super
    end

    def call
      select_for_organization if organization
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
