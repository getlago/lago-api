# frozen_string_literal: true

module Types
  module Subscriptions
    class UsageThresholdOverridesInput < Types::BaseInputObject
      argument :amount_cents, GraphQL::Types::BigInt, required: true
      argument :id, ID, required: false
      argument :recurring, Boolean, required: false
      argument :threshold_display_name, String, required: false
    end
  end
end
