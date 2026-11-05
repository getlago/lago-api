# frozen_string_literal: true

module Resolvers
  class ContractCurrentUsageTotalResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "contracts:view"

    description "Query a contract's total computed usage for the current billing period, unfiltered"

    argument :contract_id, ID, required: true

    type Types::Contracts::CurrentUsageTotal, null: false

    def resolve(contract_id:)
      contract = current_organization.contracts.find_by(id: contract_id)
      return not_found_error(resource: "contract") unless contract

      result = ::Contracts::CurrentUsageService.call(contract:, apply_taxes: true)
      return result_error(result) unless result.success?

      result
    end
  end
end
