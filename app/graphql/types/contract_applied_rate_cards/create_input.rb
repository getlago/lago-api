# frozen_string_literal: true

module Types
  module ContractAppliedRateCards
    class CreateInput < BaseInputObject
      graphql_name "CreateContractAppliedRateCardInput"
      description "Attach rate card to contract input arguments"

      argument :contract_id, ID, required: true

      argument :billing_anchor_date, GraphQL::Types::ISO8601Date, required: false
      argument :billing_scope, BillingScopeEnum, required: false
      argument :rate_card_code, String, required: true
      argument :rate_phases, [Types::RatePhases::PhaseInput], required: false
      argument :units, GraphQL::Types::Float, required: false
    end
  end
end
