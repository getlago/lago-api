# frozen_string_literal: true

module Types
  module AdjustedFees
    class CreateInput < Types::BaseInputObject
      description 'Create Adjusted Fee Input'

      argument :fee_id, ID, required: true
      argument :invoice_display_name, String, required: false
      argument :unit_precise_amount, String, required: false
      argument :units, GraphQL::Types::Float, required: false
    end
  end
end
