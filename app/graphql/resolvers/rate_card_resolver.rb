# frozen_string_literal: true

module Resolvers
  class RateCardResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "rate_cards:view"

    description "Query a single rate card of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the rate card"

    type Types::RateCards::Object, null: true

    def resolve(id: nil)
      current_organization.rate_cards.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "rate_card")
    end
  end
end
