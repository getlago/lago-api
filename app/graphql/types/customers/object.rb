# frozen_string_literal: true

module Types
  module Customers
    class Object < Types::BaseObject
      graphql_name 'Customer'

      field :id, ID, null: false
      field :subscriptions, [Types::Subscriptions::Object]
      field :invoices, [Types::Invoices::Object]

      field :customer_id, String, null: false
      field :name, String

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
