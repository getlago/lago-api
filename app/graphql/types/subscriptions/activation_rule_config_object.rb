# frozen_string_literal: true

module Types
  module Subscriptions
    class ActivationRuleConfigObject < Types::BaseObject
      graphql_name "ActivationRuleConfig"

      field :timeout_hours, Integer, null: true
    end
  end
end
