# frozen_string_literal: true

module Types
  module AdjustedFees
    class CreateInput < Types::BaseInputObject
      description 'Create Adjusted Fee Input'

      argument :fee_id, ID, required: true
      argument :invoice_display_name, String, required: false
      argument :unit_amount_cents, GraphQL::Types::BigInt, required: false
      argument :units, GraphQL::Types::Float, required: true
    end
  end
end
