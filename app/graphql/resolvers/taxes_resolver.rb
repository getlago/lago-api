# frozen_string_literal: true

module Resolvers
  class TaxesResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query taxes of an organization'

    argument :applied_to_organization, Boolean, required: false
    argument :ids, [ID], required: false, description: 'List of taxes IDs to fetch'
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::Taxes::Object.collection_type, null: false

    def resolve(applied_to_organization: nil, ids: nil, page: nil, limit: nil, search_term: nil)
      validate_organization!

      query = ::TaxesQuery.new(organization: current_organization)
      result = query.call(
        search_term:,
        page:,
        limit:,
        filters: {
          ids:,
          applied_to_organization:,
        },
      )

      result.taxes
    end
  end
end
