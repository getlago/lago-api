# frozen_string_literal: true

module Types
  module UsageMonitoring
    module Alerts
      class Object < Types::BaseObject
        graphql_name "Alert"

        field :id, ID, null: false

        field :alert_type, AlertTypeEnum, null: false
        field :billable_metric, Types::BillableMetrics::Object
        # field :organization, Types::Organizations::OrganizationType # TODO: needed?
        field :subscription_external_id, String # TODO: subscriptoin?

        field :code, String, null: false

        field :thresholds, [Types::UsageMonitoring::Alerts::ThresholdObject]

        field :created_at, GraphQL::Types::ISO8601DateTime, null: false
        field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      end
    end
  end
end
