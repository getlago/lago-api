# frozen_string_literal: true

module Resolvers
  module Customers
    class SubscriptionsResolver < Resolvers::BaseResolver
      description 'Query subscriptions of a customer'

      argument :status, [Types::Subscriptions::StatusTypeEnum], required: false do
        description 'Statuses of subscriptions to retrieve'
      end

      type Types::Subscriptions::Object, null: false

      def resolve(status: nil)
        statuses = status
        subscriptions = object.subscriptions

        return subscriptions.order(created_at: :desc) if statuses.blank?
        return subscriptions.where(status: statuses).order(created_at: :desc) unless statuses&.include?('pending')

        statuses -= ['pending']

        return subscriptions.starting_in_the_future.order(created_at: :desc) if statuses.blank?

        subscriptions.where(status: statuses).or(subscriptions.starting_in_the_future).order(created_at: :desc)
      end
    end
  end
end
