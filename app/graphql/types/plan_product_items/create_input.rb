# frozen_string_literal: true

module Types
  module PlanProductItems
    class CreateInput < BaseInputObject
      description "Create plan product item input arguments"

      argument :plan_id, ID, required: true
      argument :product_item_id, ID, required: true
      argument :rate_card_id, ID, required: true

      argument :units, GraphQL::Types::Float, required: false
    end
  end
end
