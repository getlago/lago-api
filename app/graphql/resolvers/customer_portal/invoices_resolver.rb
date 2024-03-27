# frozen_string_literal: true

module Resolvers
  module CustomerPortal
    class InvoicesResolver < Resolvers::BaseResolver
      include AuthenticableCustomerPortalUser

      description "Query invoices of a customer"

      argument :limit, Integer, required: false
      argument :page, Integer, required: false
      argument :search_term, String, required: false
      argument :status, [Types::Invoices::StatusTypeEnum], required: false

      type Types::Invoices::Object.collection_type, null: false

      def resolve(status: nil, page: nil, limit: nil, search_term: nil)
        query = InvoicesQuery.new(organization: context[:customer_portal_user].organization)
        result = query.call(
          customer_id: context[:customer_portal_user].id,
          search_term:,
          page:,
          limit:,
          status:
        )

        result.invoices
      rescue ActiveRecord::RecordNotFound
        not_found_error(resource: "customer")
      end
    end
  end
end
