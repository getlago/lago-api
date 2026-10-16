# frozen_string_literal: true

module Types
  module PlanAppliedRateCards
    class Object < Types::BaseObject
      graphql_name "PlanAppliedRateCard"
      description "Rate card applied to a plan"

      dataload_association :product, :rate_card

      field :id, ID, null: false
      field :units, GraphQL::Types::Float, null: true

      field :product, Types::Products::Object, null: false
      field :rate_card, Types::RateCards::Object, null: false

      field :rate_phases, [Types::RatePhases::Object], null: false
      field :rate_phases_count, Integer, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      def rate_phases_count
        dataloader.with(Sources::CountByForeignKey, RatePhase, :plan_rate_card_id).load(object.id)
      end

      def rate_phases
        dataloader.with(Sources::ActiveRecordAssociation, :rate_phases).load(object).sort_by(&:position)
      end
    end
  end
end
