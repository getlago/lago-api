# frozen_string_literal: true

module Types
  module Wallets
    module RecurringTransactionRules
      class Object < Types::BaseObject
        graphql_name 'RecurringTransactionRule'

        field :lago_id, ID, null: false, method: :id

        field :granted_credits, GraphQL::Types::Float, null: false
        field :interval, Types::Wallets::RecurringTransactionRules::IntervalEnum, null: true
        field :paid_credits, GraphQL::Types::Float, null: false
        field :rule_type, Types::Wallets::RecurringTransactionRules::RuleTypeEnum, null: false
        field :threshold_credits, GraphQL::Types::Float, null: true

        field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      end
    end
  end
end
