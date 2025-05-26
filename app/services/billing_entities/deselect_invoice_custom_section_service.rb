# frozen_string_literal: true

module BillingEntities
  class DeselectInvoiceCustomSectionService < BaseService
    Result = BaseResult[:billing_entity, :section]

    def initialize(section:, billing_entity:)
      @section = section
      @billing_entity = billing_entity
      super
    end

    def call
      deselect_for_billing_entity
      result
    end

    private

    attr_reader :section, :billing_entity

    def deselect_for_billing_entity
      return unless billing_entity.selected_invoice_custom_sections.include?(section)

      billing_entity.applied_invoice_custom_sections.where(
        organization_id: section.organization_id,
        invoice_custom_section_id: section.id
      ).destroy_all

      result.section = section
      result.billing_entity = billing_entity
    end
  end
end
