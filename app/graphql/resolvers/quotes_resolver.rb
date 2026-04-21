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
      return result_error(result) unless result.success?

      result.quotes.includes(:customer, :organization, :subscription, :owners)
    end
  end
end
