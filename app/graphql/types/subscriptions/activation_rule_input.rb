# frozen_string_literal: true

module Types
  module Subscriptions
    class ActivationRuleInput < Types::BaseInputObject
      argument :config, Types::Subscriptions::ActivationRuleConfigInput, required: true
      argument :type, String, required: true
    end
  end
end
