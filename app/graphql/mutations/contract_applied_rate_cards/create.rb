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

      def resolve(external_id:, **args)
        # The editable (pending) contract is the one a card can be attached to.
        contract = current_organization.contracts.live_by_external_id(external_id)

        result = ::ContractRateCards::CreateService.call(contract:, params: args)

        result.success? ? result.contract_rate_card : result_error(result)
      end
    end
  end
end
