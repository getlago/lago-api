# frozen_string_literal: true

module Types
  module RealtimeUsage
    class Point < Types::BaseObject
      graphql_name "RealtimeUsagePoint"
      description "One period of the window, broken down by dimension"

      field :breakdown, [Types::RealtimeUsage::PointUsage], null: false
      field :time, GraphQL::Types::ISO8601DateTime, null: false
      field :units, GraphQL::Types::Float, null: false
    end
  end
end
