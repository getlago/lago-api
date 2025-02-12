# frozen_string_literal: true

module BillingEntities
  class DeselectInvoiceCustomSectionService < BaseService
    def initialize(section:, billing_entity:)
      @section = section
      @billing_entity = billing_entity
      super
    end

    def call
      deselect_for_billing_entity
      result.section = section
      result
    end

    private

    attr_reader :section, :billing_entity

    def deselect_for_billing_entity
      return unless billing_entity.selected_invoice_custom_sections.include?(section)

      InvoiceCustomSectionSelection.where(
        billing_entity_id: billing_entity.id, invoice_custom_section_id: section.id
      ).destroy_all
    end
  end
end
