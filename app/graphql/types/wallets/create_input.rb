# frozen_string_literal: true

module Types
  module Wallets
    class CreateInput < Types::BaseInputObject
      description "Create Wallet Input"

      argument :currency, Types::CurrencyEnum, required: true
      argument :customer_id, ID, required: true
      argument :expiration_at, GraphQL::Types::ISO8601DateTime, required: false
      argument :granted_credits, String, required: true
      argument :invoice_requires_successful_payment, Boolean, required: false
      argument :name, String, required: false
      argument :paid_credits, String, required: true
      argument :rate_amount, String, required: true
      argument :recurring_transaction_rules, [Types::Wallets::RecurringTransactionRules::CreateInput], required: false

      argument :applies_to, Types::Wallets::AppliesToInput, required: false
    end
  end
end
