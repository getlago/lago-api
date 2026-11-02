# frozen_string_literal: true

module Types
  module RealtimeUsage
    class BillableMetric < Types::BaseObject
      graphql_name "RealtimeUsageBillableMetric"
      description "Units of a billable metric over the window, per period and per dimension"

      field :billable_metric_code, String, null: false
      field :billable_metric_id, ID, null: false
      field :billable_metric_name, String, null: false
      field :dimensions, [Types::RealtimeUsage::Dimension], null: false
      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: false
      field :points, [Types::RealtimeUsage::Point], null: false
      field :time_granularity, Types::RealtimeUsage::TimeGranularityEnum, null: false
      field :timezone, Types::TimezoneEnum, null: false
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: false
      field :units, GraphQL::Types::Float, null: false

      def billable_metric_code
        object.billable_metric.code
      end

      def billable_metric_id
        object.billable_metric.id
      end

      def billable_metric_name
        object.billable_metric.name
      end
    end
  end
end
