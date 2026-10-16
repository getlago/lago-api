# frozen_string_literal: true

module Mutations
  module ContractAppliedRateCards
    class Update < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "contracts:update"

      graphql_name "UpdateContractAppliedRateCard"
      description "Updates a rate card attached to a pending contract"

      input_object_class Types::ContractAppliedRateCards::UpdateInput
      type Types::ContractAppliedRateCards::Object

      def resolve(id:, **args)
        contract_rate_card = ContractRateCard.where(organization: current_organization).find_by(id:)

        result = ::ContractRateCards::UpdateService.call(contract_rate_card:, params: args)

        result.success? ? result.contract_rate_card : result_error(result)
      end
    end
  end
end
