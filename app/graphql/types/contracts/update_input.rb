# frozen_string_literal: true

module Types
  module Contracts
    class UpdateInput < BaseInputObject
      graphql_name "UpdateContractInput"
      description "Update contract input arguments"

      argument :external_id, String, required: true, description: "External id of the contract to update"

      argument :name, String, required: false
      # Optional: a plan-less contract prices through directly attached cards.
      argument :plan_code, String, required: false

      argument :billing_anchor_date, GraphQL::Types::ISO8601Date, required: false
      argument :billing_time, Types::Contracts::BillingTimeEnum, required: false
      argument :ended_at, GraphQL::Types::ISO8601DateTime, required: false
      argument :started_at, GraphQL::Types::ISO8601DateTime, required: false
    end
  end
end
