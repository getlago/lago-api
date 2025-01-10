# frozen_string_literal: true

module Customers
  class ManageInvoiceCustomSectionsService < BaseService
    def initialize(customer:, skip_invoice_custom_sections:, section_ids: nil, section_codes: nil)
      @customer = customer
      @section_ids = section_ids
      @section_codes = section_codes
      @skip_invoice_custom_sections = skip_invoice_custom_sections

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer
      return fail_with_double_selection if !section_ids.nil? && !section_codes.nil?
      return fail_with_invalid_params if skip_invoice_custom_sections && !(section_ids || section_codes).nil?

      ActiveRecord::Base.transaction do
        if !skip_invoice_custom_sections.nil?
          customer.selected_invoice_custom_sections = [] if !!skip_invoice_custom_sections
          customer.skip_invoice_custom_sections = skip_invoice_custom_sections
        end

        if !section_ids.nil? || !section_codes.nil?
          customer.skip_invoice_custom_sections = false
          return result if customer.applicable_invoice_custom_sections.ids == section_ids ||
            customer.applicable_invoice_custom_sections.map(&:code) == section_codes

          assign_selected_sections
        end
        customer.save!
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :customer, :section_ids, :skip_invoice_custom_sections, :section_codes

    def fail_with_double_selection
      result.validation_failure!(errors: {invoice_custom_sections: ['section_ids_and_section_codes_sent_together']})
    end

    def fail_with_invalid_params
      result.validation_failure!(errors: {invoice_custom_sections: ['skip_sections_and_selected_ids_sent_together']})
    end

    def assign_selected_sections
      # Note: when assigning organization's sections, an empty array will be sent
      if section_ids.nil?
        return customer.selected_invoice_custom_sections = customer.organization.invoice_custom_sections.where(code: section_codes)
      end

      customer.selected_invoice_custom_sections = customer.organization.invoice_custom_sections.where(id: section_ids)
    end
  end
end
