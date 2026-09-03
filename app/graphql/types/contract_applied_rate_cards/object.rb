# frozen_string_literal: true

module Types
  module ContractAppliedRateCards
    class Object < Types::BaseObject
      graphql_name "ContractAppliedRateCard"
      description "Rate card applied to a contract"

      dataload_association :product, :rate_card

      field :id, ID, null: false
      field :units, GraphQL::Types::Float, null: true

      field :product, Types::Products::Object, null: false
      field :rate_card, Types::RateCards::Object, null: false

      # The attachment's validity window, day-grained and end inclusive.
      field :billing_anchor_date, GraphQL::Types::ISO8601Date, null: false
      field :effective_date, GraphQL::Types::ISO8601Date, null: false
      field :ended_date, GraphQL::Types::ISO8601Date, null: true
      field :next_billing_at, GraphQL::Types::ISO8601DateTime, null: false

      field :rate_phases, [Types::RatePhases::Object], null: false
      field :rate_phases_count, Integer, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      def rate_phases_count
        dataloader.with(Sources::CountByForeignKey, RatePhase, :contract_rate_card_id).load(object.id)
      end

      def rate_phases
        dataloader.with(Sources::ActiveRecordAssociation, :rate_phases).load(object).sort_by(&:position)
      end
    end
  end
end
