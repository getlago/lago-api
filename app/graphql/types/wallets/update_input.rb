# frozen_string_literal: true

module Types
  module Wallets
    class UpdateInput < Types::BaseInputObject
      description "Update Wallet Input"

      argument :expiration_at, GraphQL::Types::ISO8601DateTime, required: false
      argument :id, ID, required: true
      argument :name, String, required: false
      argument :recurring_transaction_rules, [Types::Wallets::RecurringTransactionRules::UpdateInput], required: false
    end
  end
end
