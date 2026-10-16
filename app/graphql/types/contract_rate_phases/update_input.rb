# frozen_string_literal: true

module Types
  module ContractRatePhases
    class UpdateInput < BaseInputObject
      graphql_name "UpdateContractRatePhaseInput"
      description "Update a single phase of a contract rate card, addressed by its code"

      argument :code, String, required: true
      argument :contract_applied_rate_card_id, ID, required: true

      argument :billing_interval_cycle_count, Integer, required: false
      argument :name, String, required: false
      argument :new_code, String, required: false
      argument :position, Integer, required: false
      argument :rate_override, Types::RateOverrides::Input, required: false
    end
  end
end
