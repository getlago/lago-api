# frozen_string_literal: true

module Resolvers
  class InvoiceCustomSectionsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "invoice_custom_sections:view"

    description "Query invoice_custom_sections"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    type Types::InvoiceCustomSections::Object.collection_type, null: true

    def resolve(page: nil, limit: nil)
      current_organization.invoice_custom_sections
        .where(section_type: :manual)
        .joins('LEFT JOIN invoice_custom_section_selections ON invoice_custom_sections.id = invoice_custom_section_selections.invoice_custom_section_id
                AND invoice_custom_section_selections.customer_id is NULL')
        .order(
          Arel.sql("CASE WHEN invoice_custom_section_selections.id IS NOT NULL THEN 0 ELSE 1 END"),
          :name
        ).page(page).per(limit)
    end
  end
end
