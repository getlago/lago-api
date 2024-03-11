# frozen_string_literal: true

module Types
  module ChargeGroups
    class PropertiesInput < Types::BaseInputObject
      graphql_name 'ChargeGroupPropertiesInput'

      # NOTE: Standard and Package charge model
      argument :amount, String, required: false

      # NOTE: Group package charge model
      argument :free_units, GraphQL::Types::BigInt, required: false
    end
  end
end
