# frozen_string_literal: true

module Types
  module Subscriptions
    module RealtimeUsage
      class HourUsage < Types::BaseObject
        graphql_name "HourlyUsageBreakdown"
        description "Usage of a single charge filter within one hour"

        field :charge_filter_id, ID, null: true
        field :events_count, Integer, null: false
        field :units, GraphQL::Types::Float, null: false
      end
    end
  end
end
