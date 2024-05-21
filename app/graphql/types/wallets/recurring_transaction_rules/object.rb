# frozen_string_literal: true

module Types
  module Wallets
    module RecurringTransactionRules
      class Object < Types::BaseObject
        graphql_name 'RecurringTransactionRule'

        field :lago_id, ID, null: false, method: :id

        field :granted_credits, String, null: false
        field :interval, Types::Wallets::RecurringTransactionRules::IntervalEnum, null: true
        field :method, Types::Wallets::RecurringTransactionRules::MethodEnum, null: false
        field :paid_credits, String, null: false
        field :target_ongoing_balance, String, null: true
        field :threshold_credits, String, null: true
        field :trigger, Types::Wallets::RecurringTransactionRules::TriggerEnum, null: false

        field :created_at, GraphQL::Types::ISO8601DateTime, null: false

        delegate :method, to: :object
      end
    end
  end
end
