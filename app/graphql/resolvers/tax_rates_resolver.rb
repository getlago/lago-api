# frozen_string_literal: true

module Resolvers
  class TaxRatesResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query tax rates of an organization'

    argument :ids, [ID], required: false, description: 'List of tax rates IDs to fetch'
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::TaxRates::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil, search_term: nil)
      validate_organization!

      query = ::TaxRatesQuery.new(organization: current_organization)
      result = query.call(
        search_term:,
        page:,
        limit:,
        filters: {
          ids:,
        },
      )

      result.tax_rates
    end
  end
end
