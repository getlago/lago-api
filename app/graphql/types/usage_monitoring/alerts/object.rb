# frozen_string_literal: true

module Types
  module UsageMonitoring
    module Alerts
      class Object < Types::BaseObject
        graphql_name "Alert"

        field :id, ID, null: false

        field :alert_type, AlertTypeEnum, null: false
        field :billable_metric, Types::BillableMetrics::Object
        field :billable_metric_id, ID
        field :direction, DirectionEnum, null: false
        field :subscription_external_id, String
        field :wallet_id, String

        field :code, String, null: false
        field :name, String

        field :thresholds, [Types::UsageMonitoring::Alerts::ThresholdObject]

        field :last_processed_at, GraphQL::Types::ISO8601DateTime,
          description: "When the alert was last evaluated. Null means it never has been."
        field :previous_value, String, null: false,
          description: "Last observed value, judged against the threshold values and carrying the same scale."

        field :created_at, GraphQL::Types::ISO8601DateTime, null: false
        field :deleted_at, GraphQL::Types::ISO8601DateTime
        field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      end
    end
  end
end
