# frozen_string_literal: true

module Resolvers
  class RateCardRateResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "rate_cards:view"

    description "Query a single rate of a rate card"

    argument :id, ID, required: true, description: "Uniq ID of the rate"

    type Types::RateCardRates::Object, null: true

    def resolve(id: nil)
      current_organization.rate_card_rates.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "rate_card_rate")
    end
  end
end
