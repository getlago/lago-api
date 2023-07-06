# frozen_string_literal: true

module Types
  module Charges
    module AppliedTaxes
      class Object < Types::BaseObject
        graphql_name 'ChargeAppliedTax'

        field :id, ID, null: false

        field :charge, Types::Charges::Object, null: false
        field :tax, Types::Taxes::Object, null: false

        field :created_at, GraphQL::Types::ISO8601DateTime, null: false
        field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      end
    end
  end
end
