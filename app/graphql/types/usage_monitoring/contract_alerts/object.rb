# frozen_string_literal: true

module Types
  module UsageMonitoring
    module ContractAlerts
      class Object < Types::BaseObject
        graphql_name "ContractAlert"

        dataload_association :product, :product_filter

        field :id, ID, null: false

        field :alert_type, AlertTypeEnum, null: false
        field :contract_external_id, String, null: false
        field :direction, Types::UsageMonitoring::Alerts::DirectionEnum, null: false
        field :product, Types::Products::Object
        field :product_filter, Types::ProductFilters::Object

        field :code, String, null: false
        field :name, String

        field :thresholds, [Types::UsageMonitoring::Alerts::ThresholdObject], null: false

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
