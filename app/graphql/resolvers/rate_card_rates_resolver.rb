# frozen_string_literal: true

module Resolvers
  class RateCardRatesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "rate_cards:view"

    description "Query the rates of a rate card"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :rate_card_id, ID, required: true

    type Types::RateCardRates::Object.collection_type, null: false

    def resolve(rate_card_id:, page: nil, limit: nil)
      result = ::RateCardRatesQuery.call(
        organization: current_organization,
        pagination: {page:, limit:},
        filters: {rate_card_id:}
      )

      result.rate_card_rates
    end
  end
end
