# frozen_string_literal: true

module Resolvers
  class CustomersResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query customers of an organization'

    argument :ids, [String], required: false, description: 'List of customer Lago ID to fetch'
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::Customers::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil, search_term: nil)
      query = CustomersQuery.new(organization: current_organization)
      result = query.call(
        search_term:,
        page:,
        limit:,
        filters: {
          ids:,
        },
      )

      result.customers
    end
  end
end
