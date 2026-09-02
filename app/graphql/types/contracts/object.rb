# frozen_string_literal: true

module Types
  module Contracts
    class Object < Types::BaseObject
      graphql_name "Contract"
      description "The agreement a customer signed: an optional plan, a validity window and the billing anchor"

      dataload_association :customer, :plan

      field :external_id, String, null: false
      field :id, ID, null: false
      field :name, String, null: true

      field :billing_time, Types::Contracts::BillingTimeEnum, null: false
      field :status, Types::Contracts::StatusEnum, null: false

      field :billing_anchor_date, GraphQL::Types::ISO8601Date, null: true

      field :canceled_at, GraphQL::Types::ISO8601DateTime, null: true
      field :ended_at, GraphQL::Types::ISO8601DateTime, null: true
      field :started_at, GraphQL::Types::ISO8601DateTime, null: true
      field :terminated_at, GraphQL::Types::ISO8601DateTime, null: true

      field :customer, Types::Customers::Object, null: false
      # Nullable by design: a plan-less contract prices through directly
      # attached rate cards.
      field :plan, Types::Plans::Object, null: true

      field :applied_rate_cards, [Types::ContractAppliedRateCards::Object], null: false
      field :applied_rate_cards_count, Integer, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      # Ended attachments are history, not cards the contract currently
      # carries; only pay the scoped query when the field is requested.
      def applied_rate_cards
        object.applied_rate_cards.current_and_scheduled.includes(:rate_card).order(:effective_date)
      end

      def applied_rate_cards_count
        object.applied_rate_cards.current_and_scheduled.count
      end
    end
  end
end
