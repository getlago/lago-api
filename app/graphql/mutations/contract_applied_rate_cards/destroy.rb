# frozen_string_literal: true

module Mutations
  module ContractAppliedRateCards
    class Destroy < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "contracts:update"

      graphql_name "DestroyContractAppliedRateCard"
      description "Removes a rate card from a pending contract"

      argument :id, ID, required: true

      type Types::ContractAppliedRateCards::Object

      def resolve(id:)
        contract_rate_card = ContractRateCard.where(organization: current_organization).find_by(id:)

        result = ::ContractRateCards::DestroyService.call(contract_rate_card:)

        result.success? ? result.contract_rate_card : result_error(result)
      end
    end
  end
end
