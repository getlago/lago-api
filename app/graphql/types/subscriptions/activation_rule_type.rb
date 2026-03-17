# frozen_string_literal: true

module Types
  module Subscriptions
    class ActivationRuleType < Types::BaseObject
      graphql_name "SubscriptionActivationRule"

      field :lago_id, ID, null: false
      field :type, String, null: false
      field :timeout_hours, Integer, null: true
      field :status, String, null: false
      field :expires_at, GraphQL::Types::ISO8601DateTime, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
