# frozen_string_literal: true

module Invoices
  class ApplyInvoiceCustomSectionsService < BaseService
    def initialize(invoice:, resource: nil, custom_section_ids: [], skip: false)
      @invoice = invoice
      @customer = invoice.customer
      @resource = resource
      @custom_section_ids = custom_section_ids
      @skip = skip

      super()
    end

    def call
      result.applied_sections = []
      return result if skip_custom_sections?

      applicable_sections.each do |custom_section|
        invoice.applied_invoice_custom_sections.create!(
          organization_id: invoice.organization_id,
          code: custom_section.code,
          details: custom_section.details,
          display_name: custom_section.display_name,
          name: custom_section.name
        )
      end
      result.applied_sections = invoice.applied_invoice_custom_sections
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice, :customer, :resource, :custom_section_ids, :skip

    def skip_custom_sections?
      return true if skip
      return false if resource_has_custom_sections?
      return true if resource&.skip_invoice_custom_sections
      return false if custom_section_ids.present?

      customer.skip_invoice_custom_sections
    end

    def applicable_sections
      manual_sections = if custom_section_ids.present?
        organization.invoice_custom_sections.where(id: custom_section_ids)
      elsif resource_has_custom_sections?
        resource.selected_invoice_custom_sections
      else
        customer.configurable_invoice_custom_sections
      end

      manual_sections | customer.system_generated_invoice_custom_sections
    end

    def resource_has_custom_sections?
      return false unless resource
      return false unless resource.respond_to?(:selected_invoice_custom_sections)
      return false if resource.skip_invoice_custom_sections

      resource.selected_invoice_custom_sections.any?
    end

    def organization
      @organization ||= invoice.organization
    end
  end
end
