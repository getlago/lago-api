# frozen_string_literal: true

module Types
  module PlanRateCards
    class Object < Types::BaseObject
      graphql_name "PlanRateCard"
      description "Product item assigned to a plan"

      dataload_association :product_item, :rate_card

      field :id, ID, null: false
      field :units, GraphQL::Types::Float, null: true

      field :product_item, Types::ProductItems::Object, null: false
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
