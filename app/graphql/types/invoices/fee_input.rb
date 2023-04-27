# frozen_string_literal: true

module Types
  module Invoices
    class FeeInput < BaseInputObject
      description 'Fee input for creating invoice'

      argument :add_on_id, ID, required: true
      argument :unit_amount_cents, GraphQL::Types::BigInt, required: false
      argument :units, GraphQL::Types::Float, required: false
      argument :description, String, required: false
    end
  end
end
