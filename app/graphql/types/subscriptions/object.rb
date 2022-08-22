# frozen_string_literal: true

module Types
  module Subscriptions
    class Object < Types::BaseObject
      graphql_name 'Subscription'

      field :id, ID, null: false
      field :customer, Types::Customers::Object, null: false
      field :plan, Types::Plans::Object, null: false

      field :status, Types::Subscriptions::StatusTypeEnum
      field :name, String, null: true
      field :next_name, String, null: true
      field :next_pending_start_date, GraphQL::Types::ISO8601Date

      field :billing_time, Types::Subscriptions::BillingTimeEnum
      field :subscription_date, GraphQL::Types::ISO8601Date
      field :canceled_at, GraphQL::Types::ISO8601DateTime
      field :terminated_at, GraphQL::Types::ISO8601DateTime
      field :started_at, GraphQL::Types::ISO8601DateTime

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :next_plan, Types::Plans::Object

      def next_plan
        object.next_subscription&.plan
      end

      def next_name
        object.next_subscription&.name
      end

      def next_pending_start_date
        return unless object.next_subscription
        return unless object.next_subscription.pending?

        ::Subscriptions::DatesService.new_instance(object, Time.zone.today)
          .next_end_of_period(Time.zone.today) + 1.day
      end
    end
  end
end
