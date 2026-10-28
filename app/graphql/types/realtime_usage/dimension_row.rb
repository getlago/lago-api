# frozen_string_literal: true

module Types
  module RealtimeUsage
    class DimensionRow < Types::BaseObject
      graphql_name "RealtimeUsageDimensionRow"
      description "A dimension of a billable metric, with its units per period"

      field :key, String, null: false, description: "Opaque key, to pass back as a dimension filter"
      field :name, String, null: true, description: "Null for the usage of no charge filter or pricing group"
      field :points, [Types::RealtimeUsage::DimensionPoint], null: false
      field :units, GraphQL::Types::Float, null: false
    end
  end
end
