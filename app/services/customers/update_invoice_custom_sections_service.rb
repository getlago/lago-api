# frozen_string_literal: true

module Customers
  class UpdateInvoiceCustomSectionsService < BaseService
    def initialize(customer:, section_ids: [])
      @customer = customer
      @section_ids = section_ids

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer
      return result if customer.applicable_invoice_custom_sections.ids == section_ids

      if customer.organization.selected_invoice_custom_sections.ids == section_ids
        assign_organization_sections
      else
        assign_customer_sections
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :customer, :section_ids

    def assign_organization_sections
      # Note: when inheriting organization's selections, customer shouldn't have their selected sections
      customer.selected_invoice_custom_sections = []
    end

    def assign_customer_sections
      customer.selected_invoice_custom_sections = customer.applicable_invoice_custom_sections.where(id: section_ids)
    end
  end
end
