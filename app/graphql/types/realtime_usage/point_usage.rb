# frozen_string_literal: true

module Types
  module RealtimeUsage
    class PointUsage < Types::BaseObject
      graphql_name "RealtimeUsagePointBreakdown"
      description "Units of a single dimension within one period"

      field :dimension_key, String, null: false
      field :units, GraphQL::Types::Float, null: false
    end
  end
end
