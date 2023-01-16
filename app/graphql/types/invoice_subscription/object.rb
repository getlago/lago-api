# frozen_string_literal: true

module Types
  module InvoiceSubscription
    class Object < Types::BaseObject
      graphql_name 'InvoiceSubscription'

      field :invoice, Types::Invoices::Object, null: false
      field :subscription, Types::Subscriptions::Object, null: false

      field :charge_amount_cents, GraphQL::Types::BigInt, null: false
      field :subscription_amount_cents, GraphQL::Types::BigInt, null: false
      field :total_amount_cents, GraphQL::Types::BigInt, null: false

      field :fees, [Types::Fees::Object], null: true
      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: true
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: true
    end
  end
end
