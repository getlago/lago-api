# frozen_string_literal: true

module Types
  module ChargeGroups
    class Properties < Types::BaseObject
      graphql_name 'ChargeGroupProperties'

      # NOTE: Standard and Package charge model
      field :amount, String, null: true

      # NOTE: Group package charge model
      field :free_units, GraphQL::Types::BigInt, null: true
    end
  end
end
