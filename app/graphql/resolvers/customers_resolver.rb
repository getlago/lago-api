# frozen_string_literal: true

module Resolvers
  class CustomersResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "customers:view"

    description "Query customers of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    argument :search_term, String, required: false

    argument :account_type, [Types::Customers::AccountTypeEnum], required: false
    argument :with_deleted, Boolean, required: false

    type Types::Customers::Object.collection_type, null: false

    def resolve(**args)
      result = CustomersQuery.call(
        organization: current_organization,
        search_term: args[:search_term],
        pagination: {
          page: args[:page],
          limit: args[:limit]
        },
        filters: args.slice(:account_type, :with_deleted)
      )

      result.customers
    end
  end
end
