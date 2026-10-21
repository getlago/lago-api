# frozen_string_literal: true

module Resolvers
  class ContractAppliedRateCardResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "contracts:view"

    description "Query a single rate card applied to a contract"

    argument :id, ID, required: true, description: "Uniq ID of the applied rate card"

    type Types::ContractAppliedRateCards::Object, null: true

    def resolve(id: nil)
      ContractRateCard.where(organization: current_organization).find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "applied_rate_card")
    end
  end
end
