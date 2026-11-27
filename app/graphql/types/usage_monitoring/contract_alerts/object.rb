# frozen_string_literal: true

module Types
  module UsageMonitoring
    module ContractAlerts
      class Object < Types::BaseObject
        graphql_name "ContractAlert"

        field :id, ID, null: false

        field :alert_type, AlertTypeEnum, null: false
        field :contract_external_id, String, null: false
        field :direction, Types::UsageMonitoring::Alerts::DirectionEnum, null: false
        field :scope, [ScopeObject], null: false

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

        def scope
          product = dataloader.with(Sources::ActiveRecordAssociation, :product).load(object)
          product_filter = dataloader.with(Sources::ActiveRecordAssociation, :product_filter).load(object)
          return [] unless product

          target = product_filter ? {product_filters: [product_filter]} : {with_product_filters: object.with_product_filters}

          [{type: "contract", product:, **target}]
        end

        # Same order as the REST serializer: one-time thresholds by value, then the recurring one
        def thresholds
          object.thresholds.sort_by { [it.recurring ? 1 : 0, it.value] }
        end
      end
    end
  end
end
