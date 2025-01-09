# frozen_string_literal: true

module Customers
  class ManageInvoiceCustomSectionsService < BaseService
    def initialize(customer:, skip_invoice_custom_sections:, section_ids:)
      @customer = customer
      @section_ids = section_ids
      @skip_invoice_custom_sections = skip_invoice_custom_sections

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer
      raise_invalid_params if skip_invoice_custom_sections && section_ids.present?

      ActiveRecord::Base.transaction do
        unless skip_invoice_custom_sections.nil?
          customer.selected_invoice_custom_sections = [] if !!skip_invoice_custom_sections
          customer.skip_invoice_custom_sections = skip_invoice_custom_sections
        end

        unless section_ids.nil?
          customer.skip_invoice_custom_sections = false
          return result if customer.applicable_invoice_custom_sections.ids == section_ids

          assign_selected_sections
        end
        customer.save!
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :customer, :section_ids, :skip_invoice_custom_sections

    def raise_invalid_params
      result.validation_failure!(errors: {invoice_custom_sections: ['skip_sections_and_selected_ids_sent_together']})
    end

    def assign_selected_sections
      # Note: when assigning organization's sections, an empty array will be sent
      customer.selected_invoice_custom_sections = customer.organization.invoice_custom_sections.where(id: section_ids)
    end
  end
end
