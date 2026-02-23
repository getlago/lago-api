# frozen_string_literal: true

module Types
  module Subscriptions
    class ActivationRuleConfigInput < Types::BaseInputObject
      argument :timeout_hours, Integer, required: true
    end
  end
end
