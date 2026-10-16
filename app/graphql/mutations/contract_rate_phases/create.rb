# frozen_string_literal: true

module Mutations
  module ContractRatePhases
    class Create < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "contracts:update"

      graphql_name "CreateContractRatePhase"
      description "Inserts a phase into a contract rate card's sequence"

      input_object_class Types::ContractRatePhases::CreateInput
      type Types::RatePhases::Object

      def resolve(**args)
        contract_rate_card = ContractRateCard
          .where(organization: current_organization)
          .find_by(id: args[:contract_applied_rate_card_id])

        result = ::RatePhases::CreateService.call(
          contract_rate_card:,
          params: args.except(:contract_applied_rate_card_id)
        )

        result.success? ? result.rate_phase : result_error(result)
      end
    end
  end
end
