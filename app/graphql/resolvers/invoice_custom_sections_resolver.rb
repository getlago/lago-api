# frozen_string_literal: true

module Resolvers
  class InvoiceCustomSectionsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = 'invoice_custom_sections:view'

    description "Query invoice_custom_sections"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    type Types::InvoiceCustomSections::Object.collection_type, null: true

    def resolve(page: nil, limit: nil)
      current_organization.invoice_custom_sections.left_outer_joins(:invoice_custom_section_selections).order(
        Arel.sql('CASE WHEN invoice_custom_section_selections.id IS NOT NULL THEN 0 ELSE 1 END'),
        :name
      ).page(page).per(limit)
    end
  end
end
