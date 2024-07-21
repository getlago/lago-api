# frozen_string_literal: true

module Resolvers
  class CustomersResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = 'customers:view'

    description 'Query customers of an organization'

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::Customers::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, search_term: nil)
      result = CustomersQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {
          page:,
          limit:
        }
      )

      result.customers
    end
  end
end
