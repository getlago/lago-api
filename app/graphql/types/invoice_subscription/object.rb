# frozen_string_literal: true

module Types
  module InvoiceSubscription
    class Object < Types::BaseObject
      graphql_name 'InvoiceSubscription'

      field :invoice, Types::Invoices::Object, null: false
      field :subscription, Types::Subscriptions::Object, null: false

      field :charge_amount_cents, Integer, null: false
      field :subscription_amount_cents, Integer, null: false
      field :total_amount_cents, Integer, null: false

      field :fees, [Types::Fees::Object], null: true
      field :from_date, GraphQL::Types::ISO8601Date, null: false
      field :to_date, GraphQL::Types::ISO8601Date, null: false
    end
  end
end
