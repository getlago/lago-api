# frozen_string_literal: true

module Types
  module PlanAppliedRateCards
    class CreateInput < BaseInputObject
      description "Create plan product input arguments"

      argument :plan_id, ID, required: true
      argument :rate_card_code, String, required: true

      argument :units, GraphQL::Types::Float, required: false
    end
  end
end
