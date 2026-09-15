# frozen_string_literal: true

module Types
  module Contracts
    class CreateInput < BaseInputObject
      graphql_name "CreateContractInput"
      description "Create contract input arguments"

      argument :external_customer_id, String, required: true
      argument :external_id, String, required: true
      argument :name, String, required: false
      # Optional by design: a plan-less contract prices through directly
      # attached rate cards.
      argument :plan_code, String, required: false

      argument :billing_anchor_date, GraphQL::Types::ISO8601Date, required: false
      argument :billing_time, Types::Contracts::BillingTimeEnum, required: false
      argument :ended_at, GraphQL::Types::ISO8601DateTime, required: false
      argument :started_at, GraphQL::Types::ISO8601DateTime, required: false
    end
  end
end
