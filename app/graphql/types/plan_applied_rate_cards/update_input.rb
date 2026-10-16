# frozen_string_literal: true

module Types
  module PlanAppliedRateCards
    class UpdateInput < BaseInputObject
      graphql_name "UpdatePlanAppliedRateCardInput"
      description "Update plan applied rate card input arguments"

      argument :id, ID, required: true

      argument :units, GraphQL::Types::Float, required: false
    end
  end
end
