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
        subscriptions = object.subscriptions
        subscriptions = subscriptions.where(status: status) if status.present?
        subscriptions.order(created_at: :desc)
      end
    end
  end
end
