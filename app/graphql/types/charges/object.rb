# frozen_string_literal: true

module Types
  module Charges
    class Object < Types::BaseObject
      graphql_name 'Charge'

      field :id, ID, null: false
      field :billable_metric, Types::BillableMetrics::Object, null: false
      field :charge_model, Types::Charges::ChargeModelEnum, null: false
      field :properties, Types::Charges::Properties, null: true
      field :group_properties, [Types::Charges::GroupProperties], null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true

      def billable_metric
        return object.billable_metric unless object.discarded?

        BillableMetric.with_discarded.find_by(id: object.billable_metric_id)
      end

      def group_properties
        scope = object.group_properties
        scope = scope.with_discarded if object.discarded?
        scope
      end
    end
  end
end
