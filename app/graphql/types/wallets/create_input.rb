# frozen_string_literal: true

module Types
  module Wallets
    class CreateInput < Types::BaseInputObject
      description "Create Wallet Input"

      argument :billing_entity_id, ID, required: false
      argument :code, String, required: false
      argument :currency, Types::CurrencyEnum, required: true
      argument :customer_id, ID, required: true
      argument :expiration_at, GraphQL::Types::ISO8601DateTime, required: false
      argument :invoice_requires_successful_payment, Boolean, required: false
      argument :name, String, required: false
      argument :priority, Integer, required: true
      argument :purchase_order_number, String, required: false
      argument :rate_amount, String, required: true

      # NOTE: The app no longer creates a transaction when creating a wallet. These arguments only
      #       stay until the front-end stops sending them, then they will be removed.
      argument :granted_credits, String,
        required: false,
        deprecation_reason: "The app no longer creates a transaction on wallet creation. Use createCustomerWalletTransaction."
      argument :ignore_paid_top_up_limits_on_creation, Boolean,
        required: false,
        deprecation_reason: "The app no longer creates a transaction on wallet creation. Use createCustomerWalletTransaction."
      argument :paid_credits, String,
        required: false,
        deprecation_reason: "The app no longer creates a transaction on wallet creation. Use createCustomerWalletTransaction."
      argument :transaction_name, String,
        required: false,
        deprecation_reason: "The app no longer creates a transaction on wallet creation. Use createCustomerWalletTransaction."

      argument :paid_top_up_max_amount_cents, GraphQL::Types::BigInt, required: false
      argument :paid_top_up_min_amount_cents, GraphQL::Types::BigInt, required: false

      argument :recurring_transaction_rules, [Types::Wallets::RecurringTransactionRules::CreateInput], required: false

      argument :invoice_custom_section, Types::InvoiceCustomSections::ReferenceInput, required: false

      argument :applies_to, Types::Wallets::AppliesToInput, required: false

      argument :metadata, [Types::Metadata::Input], required: false, **Types::Metadata::Input::ARGUMENT_OPTIONS

      argument :payment_method, Types::PaymentMethods::ReferenceInput, required: false

      argument :connections, Types::Connections::Input, required: false
    end
  end
end
