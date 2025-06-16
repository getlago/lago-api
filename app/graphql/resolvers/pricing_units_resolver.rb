# frozen_string_literal: true

module Resolvers
  class PricingUnitsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "pricing_units:view"

    description "Query the pricing units of current organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    type Types::PricingUnits::Object.collection_type, null: false

    def resolve(page: nil, limit: nil)
      current_organization.pricing_units.order(created_at: :asc).page(page).per(limit)
    end
  end
end
