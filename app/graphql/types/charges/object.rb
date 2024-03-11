# frozen_string_literal: true

module Types
  module Charges
    class Object < Types::BaseObject
      graphql_name 'Charge'

      field :id, ID, null: false
      field :invoice_display_name, String, null: true

      field :billable_metric, Types::BillableMetrics::Object, null: false
      field :charge_group, Types::ChargeGroups::Object, null: true
      field :charge_model, Types::Charges::ChargeModelEnum, null: false
      field :group_properties, [Types::Charges::GroupProperties], null: true
      field :invoiceable, Boolean, null: false
      field :min_amount_cents, GraphQL::Types::BigInt, null: false
      field :pay_in_advance, Boolean, null: false
      field :properties, Types::Charges::Properties, null: true
      field :prorated, Boolean, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :taxes, [Types::Taxes::Object]

      def billable_metric
        return object.billable_metric unless object.discarded?

        BillableMetric.with_discarded.find_by(id: object.billable_metric_id)
      end

      def group_properties
        scope = object.group_properties
        scope = scope.with_discarded if object.discarded?
        scope.includes(:group).sort_by { |gp| gp.group&.name }
      end

      def charge_group
        return object.charge_group unless object.discarded?

        ChargeGroup.with_discarded.find_by(id: object.charge_group_id)
      end
    end
  end
end
