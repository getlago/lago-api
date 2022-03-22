# frozen_string_literal: true

module Resolvers
  class ProductsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query products of an organization'

    argument :page, Integer, required: false
    argument :limit, Integer, required: false

    type Types::Products::Object.collection_type, null: false

    def resolve(page: nil, limit: nil)
      current_organization
        .products
        .page(page)
        .per(limit)
    end
  end
end
