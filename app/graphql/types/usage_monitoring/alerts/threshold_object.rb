# frozen_string_literal: true

module Types
  module UsageMonitoring
    module Alerts
      class ThresholdObject < Types::BaseObject
        graphql_name "AlertThreshold"

        # field :id, ID, null: false

        # TODO: RECURRING

        # field :alert, Object, null: false

        field :code, String, null: false
        field :value, String, null: false

        # field :created_at, GraphQL::Types::ISO8601DateTime, null: false
        # field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      end
    end
  end
end
