# frozen_string_literal: true

module Types
  module Fees
    module AmountDetails
      class GraduatedRange < Types::BaseObject
        graphql_name 'FeeAmountDetailsGraduatedRange'

        field :flat_unit_amount, String, null: true
        field :from_value, Integer, null: true
        field :per_unit_amount, String, null: true
        field :per_unit_total_amount, String, null: true
        field :to_value, Integer, null: true
        field :total_with_flat_amount, String, null: true
        field :units, String, null: true
      end
    end
  end
end
