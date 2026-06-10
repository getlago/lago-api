# frozen_string_literal: true

module Resolvers
  class ProductsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "products:view"

    description "Query products of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::Products::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, search_term: nil)
      result = ::ProductsQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {page:, limit:}
      )

      result.products
    end
  end
end
