# frozen_string_literal: true

module Types
  module RateProperties
    class PercentageTier < Types::BaseObject
      graphql_name "RatePercentageTier"

      field :to_value, String, null: true

      field :flat_amount, String, null: false
      field :rate, String, null: false
    end
  end
end
