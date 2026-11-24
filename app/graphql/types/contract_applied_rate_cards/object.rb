# frozen_string_literal: true

module Types
  module ContractAppliedRateCards
    class Object < Types::BaseObject
      graphql_name "ContractAppliedRateCard"
      description "Rate card applied to a contract"

      dataload_association :contract, :product, :rate_card

      field :id, ID, null: false
      field :scheduled_units, GraphQL::Types::Float, null: true
      field :scheduled_units_effective_at, GraphQL::Types::ISO8601DateTime, null: true
      field :units, GraphQL::Types::Float, null: true

      field :contract, Types::Contracts::Object, null: false
      field :product, Types::Products::Object, null: false
      field :rate_card, Types::RateCards::Object, null: false

      field :billing_anchor_date, GraphQL::Types::ISO8601Date, null: false
      field :effective_date, GraphQL::Types::ISO8601Date, null: false
      field :next_billing_at, GraphQL::Types::ISO8601DateTime, null: true

      field :rate_phases, [Types::RatePhases::Object], null: false
      field :rate_phases_count, Integer, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      delegate :units, to: :units_state

      def scheduled_units
        units_state.scheduled_term&.units
      end

      def scheduled_units_effective_at
        units_state.scheduled_term&.starts_at
      end

      def rate_phases_count
        dataloader.with(Sources::CountByForeignKey, RatePhase, :contract_rate_card_id).load(object.id)
      end

      def rate_phases
        dataloader.with(Sources::ActiveRecordAssociation, :rate_phases).load(object).sort_by(&:position)
      end

      private

      def units_state
        @units_state ||= begin
          dataloader.with(Sources::ActiveRecordAssociation, :terms).load(object)
          contract = dataloader.with(Sources::ActiveRecordAssociation, :contract).load(object)
          dataloader.with(Sources::ActiveRecordAssociation, :customer).load(contract)
          timestamp = contract.editable? ? object.effective_date.in_time_zone(contract.customer.applicable_timezone) : Time.current
          ::ContractRateCards::UnitsAtService.call!(contract_rate_card: object, timestamp:)
        end
      end
    end
  end
end
