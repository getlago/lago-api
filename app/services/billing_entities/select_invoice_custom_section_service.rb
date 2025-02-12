# frozen_string_literal: true

module BillingEntities
  class SelectInvoiceCustomSectionService < BaseService
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

      billing_entity.selected_invoice_custom_sections << section
      result.billing_entity = billing_entity
    end
  end
end
