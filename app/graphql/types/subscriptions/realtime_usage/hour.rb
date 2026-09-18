# frozen_string_literal: true

module Types
  module Subscriptions
    module RealtimeUsage
      class Hour < Types::BaseObject
        graphql_name "HourlyUsagePoint"
        description "One hour of the window, broken down by charge filter"

        field :breakdown, [Types::Subscriptions::RealtimeUsage::HourUsage], null: false, method: :usages
        field :events_count, Integer, null: false
        field :time, GraphQL::Types::ISO8601DateTime, null: false
        field :units, GraphQL::Types::Float, null: false
      end
    end
  end
end
