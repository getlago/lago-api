# frozen_string_literal: true

module Types
  module Subscriptions
    class ActivationRuleInput < Types::BaseInputObject
      graphql_name "SubscriptionActivationRuleInput"

      argument :timeout_hours, Integer, required: false
      argument :type, String, required: true
    end
  end
end
