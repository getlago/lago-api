# frozen_string_literal: true

module Types
  module RealtimeUsage
    class Events < Types::BaseObject
      graphql_name "RealtimeUsageEvents"
      description "Events counted on the usage-based charges of the organization, per period"

      field :events_count, GraphQL::Types::BigInt, null: false
      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: false
      field :last_ingested_at, GraphQL::Types::ISO8601DateTime, null: true
      field :points, [Types::RealtimeUsage::EventsPoint], null: false
      field :time_granularity, Types::RealtimeUsage::TimeGranularityEnum, null: false
      field :timezone, Types::TimezoneEnum, null: false
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
