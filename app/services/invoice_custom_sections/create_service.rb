# frozen_string_literal: true

module InvoiceCustomSections
  class CreateService < BaseService
    Result = BaseResult[:invoice_custom_section]

    def initialize(organization:, create_params:, selected: false)
      @organization = organization
      @create_params = create_params
      @selected = selected
      super
    end

    def call
      invoice_custom_section = organization.invoice_custom_sections.create!(create_params)

      if selected
        BillingEntities::SelectInvoiceCustomSectionService.call!(
          section: invoice_custom_section,
          billing_entity: organization.default_billing_entity
        )
      end

      result.invoice_custom_section = invoice_custom_section
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :create_params, :selected
  end
end
