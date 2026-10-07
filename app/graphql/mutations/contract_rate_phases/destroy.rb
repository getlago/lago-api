# frozen_string_literal: true

module Mutations
  module ContractRatePhases
    class Destroy < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "contracts:update"

      graphql_name "DestroyContractRatePhase"
      description "Removes a single phase of a contract rate card; the indefinite terminal phase cannot be removed"

      argument :code, String, required: true
      argument :contract_applied_rate_card_id, ID, required: true

      type Types::RatePhases::Object

      def resolve(**args)
        contract_rate_card = ContractRateCard
          .where(organization: current_organization)
          .find_by(id: args[:contract_applied_rate_card_id])

        rate_phase = contract_rate_card&.rate_phases&.find_by(code: args[:code])

        result = ::RatePhases::DestroyService.call(rate_phase:)

        result.success? ? result.rate_phase : result_error(result)
      end
    end
  end
end
