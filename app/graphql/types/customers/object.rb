# frozen_string_literal: true

module Types
  module Customers
    class Object < Types::BaseObject
      graphql_name 'Customer'

      field :id, ID, null: false

      field :customer_id, String, null: false
      field :name, String
      field :subscriptions, [Types::Subscriptions::Object]

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :can_be_deleted, Boolean, null: false do
        description 'Check if customer is deletable'
      end

      def can_be_deleted
        object.deletable?
      end
    end
  end
end
