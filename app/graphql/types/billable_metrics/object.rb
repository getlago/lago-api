# frozen_string_literal: true

module Types
  module BillableMetrics
    class Object < Types::BaseObject
      graphql_name "BillableMetric"
      description "Base billable metric"

      field :id, ID, null: false
      field :organization, Types::OrganizationType

      field :code, String, null: false
      field :name, String, null: false

      field :description, String

      field :aggregation_type, Types::BillableMetrics::AggregationTypeEnum, null: false
      field :field_name, String, null: true
      field :weighted_interval, Types::BillableMetrics::WeightedIntervalEnum, null: true

      field :filters, [Types::BillableMetricFilters::Object], null: true
      field :flat_groups, [Types::Groups::Object], null: true, method: :selectable_groups
      field :group, GraphQL::Types::JSON, null: true, method: :active_groups_as_tree

      field :active_subscriptions_count, Integer, null: false
      field :draft_invoices_count, Integer, null: false
      field :plans_count, Integer, null: false
      field :recurring, Boolean, null: false
      field :subscriptions_count, Integer, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      def subscriptions_count
        object.plans.joins(:subscriptions).count
      end

      def active_subscriptions_count
        object.plans.joins(:subscriptions).merge(Subscription.active).count
      end

      def draft_invoices_count
        object.charges
          .joins(fees: [:invoice])
          .merge(Invoice.draft)
          .select(:invoice_id)
          .distinct
          .count
      end

      def plans_count
        object.plans.distinct.count
      end
    end
  end
end
