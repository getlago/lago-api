# frozen_string_literal: true

module Resolvers
  module Customers
    class InvoiceCustomSectionsResolver < Resolvers::BaseResolver
      include RequiredOrganization
      description 'Query selected invoice_custom_sections of a customer'

      argument :customer_id, type: ID, required: true
      argument :limit, Integer, required: false
      argument :page, Integer, required: false

      type Types::InvoiceCustomSections::Object.collection_type, null: true
      def resolve(customer_id:, page: nil, limit: nil)
        customer = current_organization.customers.find(customer_id)
        customer.applicable_invoice_custom_sections.page(page).per(limit)
      rescue ActiveRecord::RecordNotFound
        not_found_error(resource: 'customer')
      end
    end
  end
end
