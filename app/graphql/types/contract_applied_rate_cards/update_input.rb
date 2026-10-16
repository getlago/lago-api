# frozen_string_literal: true

module Types
  module ContractAppliedRateCards
    class UpdateInput < BaseInputObject
      graphql_name "UpdateContractAppliedRateCardInput"
      description "Update contract applied rate card input arguments"

      argument :id, ID, required: true

      argument :billing_anchor_date, GraphQL::Types::ISO8601Date, required: false
      argument :units, GraphQL::Types::Float, required: false
    end
  end
end
