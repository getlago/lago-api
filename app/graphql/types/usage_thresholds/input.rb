# frozen_string_literal: true

module Types
  module UsageThresholds
    class Input < BaseInputObject
      graphql_name "UsageThresholdInput"

      argument :id, ID, required: false

      argument :amount_cents, GraphQL::Types::BigInt, required: false
      argument :recurring, Boolean, required: false
      argument :threshold_display_name, String, required: false
    end
  end
end
