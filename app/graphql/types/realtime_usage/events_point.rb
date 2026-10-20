# frozen_string_literal: true

module Types
  module RealtimeUsage
    class EventsPoint < Types::BaseObject
      graphql_name "RealtimeUsageEventsPoint"
      description "Events counted in one period of the window"

      field :events_count, GraphQL::Types::BigInt, null: false
      field :time, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
