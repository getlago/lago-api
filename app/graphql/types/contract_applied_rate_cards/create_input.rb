# frozen_string_literal: true

module Types
  module ContractAppliedRateCards
    class CreateInput < BaseInputObject
      graphql_name "CreateContractAppliedRateCardInput"
      description "Attach rate card to contract input arguments"

      argument :external_id, String, required: true, description: "External id of the contract"

      argument :billing_anchor_date, GraphQL::Types::ISO8601Date, required: false
      argument :rate_card_code, String, required: true
      argument :rate_phases, [Types::RatePhases::PhaseInput], required: false
      argument :units, GraphQL::Types::Float, required: false
    end
  end
end
