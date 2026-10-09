# frozen_string_literal: true

module Types
  module Subscriptions
    module RealtimeUsage
      class Hourly < Types::BaseObject
        graphql_name "SubscriptionHourlyUsage"
        description "Realtime usage of a charge, per hour and per charge filter"

        field :aggregation_type, Types::BillableMetrics::AggregationTypeEnum, null: false
        field :filters, [Types::Subscriptions::RealtimeUsage::Filter], null: false
        field :from_datetime, GraphQL::Types::ISO8601DateTime, null: false
        field :hours, [Types::Subscriptions::RealtimeUsage::Hour], null: false
        field :last_ingested_at, GraphQL::Types::ISO8601DateTime, null: true
        field :timezone, Types::TimezoneEnum, null: false
        field :to_datetime, GraphQL::Types::ISO8601DateTime, null: false
      end
    end
  end
end
