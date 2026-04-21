# frozen_string_literal: true

module Resolvers
  class QuotesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "quotes:view"

    description "Query quotes of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    type Types::Quotes::Object.collection_type, null: false

    def resolve(page: nil, limit: nil)
      result = ::QuotesQuery.call(
        organization: current_organization,
        pagination: {
          page:,
          limit:
        }
      )

      result.quotes.includes(:customer, :organization, :owners)
    end
  end
end
