# frozen_string_literal: true

module Resolvers
  class CustomersResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query customers of an organization'

    argument :ids, [String], required: false, description: 'List of customer Lago ID to fetch'
    argument :page, Integer, required: false
    argument :limit, Integer, required: false

    type Types::Customers::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil)
      validate_organization!

      customers = current_organization
        .customers
        .page(page)
        .per(limit)

      customers = customers.where(id: ids) if ids.present?

      customers
    end
  end
end
