# frozen_string_literal: true

module Types
  module UsageMonitoring
    module Alerts
      class ThresholdObject < Types::BaseObject
        graphql_name "AlertThreshold"

        field :id, ID, null: false

        # TODO: DESCRIPTION
        # TODO: RECURRING

        field :alert, Object, null: false
        field :subscription_external_id, String # TODO: subscription?

        field :code, String, null: false
        field :value, GraphQL::Types::Float, null: false

        field :created_at, GraphQL::Types::ISO8601DateTime, null: false
        field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      end
    end
  end
end
