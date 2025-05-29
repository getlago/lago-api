# frozen_string_literal: true

module BillingEntities
  class SelectInvoiceCustomSectionService < BaseService
    Result = BaseResult[:billing_entity, :section]

    def initialize(section:, billing_entity:)
      @section = section
      @billing_entity = billing_entity

      super
    end

    def call
      select_for_billing_entity
      result
    end

    private

    attr_reader :section, :billing_entity

    def select_for_billing_entity
      return if billing_entity.selected_invoice_custom_sections.include?(section)

      billing_entity.applied_invoice_custom_sections.create!(
        organization_id: section.organization_id,
        billing_entity:,
        invoice_custom_section: section
      )

      result.billing_entity = billing_entity
      result.section = section
    end
  end
end
