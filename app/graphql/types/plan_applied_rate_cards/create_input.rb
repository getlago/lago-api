# frozen_string_literal: true

module Types
  module PlanAppliedRateCards
    class CreateInput < BaseInputObject
      description "Apply rate card to plan input arguments"

      argument :plan_id, ID, required: true
      argument :rate_card_code, String, required: true
      argument :rate_phases, [Types::RatePhases::PhaseInput], required: false

      argument :units, GraphQL::Types::Float, required: false
    end
  end
end
