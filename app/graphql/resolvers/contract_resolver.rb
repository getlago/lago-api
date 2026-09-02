# frozen_string_literal: true

module Resolvers
  class ContractResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "contracts:view"

    description "Query a single contract of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the contract"

    type Types::Contracts::Object, null: true

    def resolve(id: nil)
      current_organization.contracts.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "contract")
    end
  end
end
