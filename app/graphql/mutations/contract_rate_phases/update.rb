# frozen_string_literal: true

module Mutations
  module ContractRatePhases
    class Update < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "contracts:update"

      graphql_name "UpdateContractRatePhase"
      description "Updates a single phase of a contract rate card, addressed by its code"

      input_object_class Types::ContractRatePhases::UpdateInput
      type Types::RatePhases::Object

      def resolve(**args)
        contract_rate_card = ContractRateCard
          .where(organization: current_organization)
          .find_by(id: args[:contract_applied_rate_card_id])

        rate_phase = contract_rate_card&.rate_phases&.find_by(code: args[:code])

        params = args.except(:contract_applied_rate_card_id, :code, :new_code)
        params[:code] = args[:new_code] if args.key?(:new_code)

        result = ::RatePhases::UpdateService.call(rate_phase:, params:)

        result.success? ? result.rate_phase : result_error(result)
      end
    end
  end
end
