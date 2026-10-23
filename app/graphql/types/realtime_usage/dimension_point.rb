# frozen_string_literal: true

module Types
  module RealtimeUsage
    class DimensionPoint < Types::BaseObject
      graphql_name "RealtimeUsageDimensionPoint"
      description "Units of a dimension within one period"

      field :time, GraphQL::Types::ISO8601DateTime, null: false
      field :units, GraphQL::Types::Float, null: false
    end
  end
end
