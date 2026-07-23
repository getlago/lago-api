# frozen_string_literal: true

module Types
  module PlanRateCards
    class CreateInput < BaseInputObject
      description "Create plan product item input arguments"

      argument :plan_id, ID, required: true
      argument :rate_card_code, String, required: true

      argument :units, GraphQL::Types::Float, required: false
    end
  end
end
