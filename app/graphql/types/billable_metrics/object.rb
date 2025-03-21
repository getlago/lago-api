# frozen_string_literal: true

module Types
  module BillableMetrics
    class Object < Types::BaseObject
      graphql_name "BillableMetric"
      description "Base billable metric"

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType

      field :code, String, null: false
      field :name, String, null: false

      field :description, String

      field :aggregation_type, Types::BillableMetrics::AggregationTypeEnum, null: false
      field :expression, String, null: true
      field :field_name, String, null: true
      field :weighted_interval, Types::BillableMetrics::WeightedIntervalEnum, null: true

      field :filters, [Types::BillableMetricFilters::Object], null: true

      field :active_subscriptions_count, Integer, null: false
      field :draft_invoices_count, Integer, null: false
      field :plans_count, Integer, null: false
      field :recurring, Boolean, null: false
      field :subscriptions_count, Integer, null: false

      field :rounding_function, Types::BillableMetrics::RoundingFunctionEnum, null: true
      field :rounding_precision, Integer, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :integration_mappings, [Types::IntegrationMappings::Object], null: true do
        argument :integration_id, ID, required: false
      end

      def subscriptions_count
        Subscription.where(plan_id: object.charges.select(:plan_id).distinct).count
      end

      def active_subscriptions_count
        Subscription.active.where(plan_id: object.charges.select(:plan_id).distinct).count
      end

      def draft_invoices_count
        Invoice.draft.where(id: object.charges
          .joins(:fees)
          .select(:invoice_id)).count
      end

      def plans_count
        object.charges.distinct.count(:plan_id)
      end

      def integration_mappings(integration_id: nil)
        mappings = object.integration_mappings
        mappings = mappings.where(integration_id:) if integration_id
        mappings
      end
    end
  end
end
