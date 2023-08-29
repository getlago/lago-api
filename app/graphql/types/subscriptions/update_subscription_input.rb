# frozen_string_literal: true

module Types
  module Subscriptions
    class UpdateSubscriptionInput < BaseInputObject
      description 'Update Subscription input arguments'

      argument :ending_at, GraphQL::Types::ISO8601DateTime, required: false
      argument :id, ID, required: true
      argument :name, String, required: false
      argument :subscription_at, GraphQL::Types::ISO8601DateTime, required: false
    end
  end
end
