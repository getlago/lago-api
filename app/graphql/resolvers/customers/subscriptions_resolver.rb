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

        if statuses&.include?('pending')
          pending_subscriptions = subscriptions.pending.where(previous_subscription: nil)
          statuses -= ['pending']

          subscriptions = subscriptions.where(status: statuses) if statuses.present?
          subscriptions = subscriptions.or(pending_subscriptions)
        elsif statuses.present?
          subscriptions = subscriptions.where(status: statuses)
        end

        subscriptions.order(created_at: :desc)
      end
    end
  end
end
