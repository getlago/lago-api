# frozen_string_literal: true

module Types
  module PlanAppliedRateCards
    class Object < Types::BaseObject
      graphql_name "PlanAppliedRateCard"
      description "ProductCategory item assigned to a plan"

      dataload_association :product, :rate_card

      field :id, ID, null: false
      field :units, GraphQL::Types::Float, null: true

      field :product, Types::Products::Object, null: false
      field :rate_card, Types::RateCards::Object, null: false

      field :rate_phases_count, Integer, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      def rate_phases_count
        object.rate_phases.count
      end
    end
  end
end
