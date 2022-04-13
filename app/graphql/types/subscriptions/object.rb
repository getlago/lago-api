# frozen_string_literal: true

module Types
  module Subscriptions
    class Object < Types::BaseObject
      graphql_name 'Subscription'

      field :id, ID, null: false
      field :customer, Types::Customers::Object, null: false
      field :plan, Types::Plans::Object, null: false

      field :status, Types::Subscriptions::StatusTypeEnum

      field :anniversary_date, GraphQL::Types::ISO8601Date
      field :canceled_at, GraphQL::Types::ISO8601DateTime
      field :terminated_at, GraphQL::Types::ISO8601DateTime
      field :started_at, GraphQL::Types::ISO8601DateTime

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :next_plan, Types::Plans::Object

      def next_plan
        object.next_subscription&.plan
      end
    end
  end
end
