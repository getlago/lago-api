# frozen_string_literal: true

module Mutations
  module ContractAppliedRateCards
    class Create < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "contracts:update"

      graphql_name "CreateContractAppliedRateCard"
      description "Attaches a rate card to a pending contract"

      input_object_class Types::ContractAppliedRateCards::CreateInput
      type Types::ContractAppliedRateCards::Object

      def resolve(contract_id:, **args)
        contract = current_organization.contracts.find_by(id: contract_id)

        result = ::ContractRateCards::CreateService.call(contract:, params: args)

        result.success? ? result.contract_rate_card : result_error(result)
      end
    end
  end
end
