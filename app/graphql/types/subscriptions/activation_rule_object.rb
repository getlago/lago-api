# frozen_string_literal: true

module Types
  module Subscriptions
    class ActivationRuleObject < Types::BaseObject
      graphql_name "ActivationRule"

      field :config, Types::Subscriptions::ActivationRuleConfigObject, null: true
      field :type, String, null: false
    end
  end
end
