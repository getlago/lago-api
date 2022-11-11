# frozen_string_literal: true

module Types
  module BillableMetrics
    class Object < Types::BaseObject
      graphql_name 'BillableMetric'

      field :id, ID, null: false
      field :organization, Types::OrganizationType

      field :name, String, null: false
      field :code, String, null: false
      field :description, String
      field :aggregation_type, Types::BillableMetrics::AggregationTypeEnum, null: false
      field :field_name, String, null: true
      field :group, GraphQL::Types::JSON, null: true
      field :flat_groups, [Types::Groups::Object], null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :can_be_deleted, Boolean, null: false do
        description 'Check if billable metric is deletable'
      end

      def can_be_deleted
        object.deletable?
      end

      def group
        object.active_groups_as_tree
      end

      def flat_groups
        object.selectable_groups
      end
    end
  end
end
