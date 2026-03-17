# frozen_string_literal: true

module Types
  module Subscriptions
    class ActivationRuleInput < BaseInputObject
      description "Activation Rule input arguments"

      argument :type, String, required: true
      argument :timeout_hours, Integer, required: true
    end
  end
end
