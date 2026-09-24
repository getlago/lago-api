# frozen_string_literal: true

module Types
  module Contracts
    class UpdateInput < BaseInputObject
      graphql_name "UpdateContractInput"
      description "Update contract input arguments"

      argument :external_id, String, required: false, description: "External id of the contract to update, resolving to the pending contract when an active one shares it"
      argument :id, ID, required: false, description: "Unique ID of the contract to update"

      validates required: {one_of: [:id, :external_id]}

      argument :name, String, required: false
      # Optional: a plan-less contract prices through directly attached cards.
      argument :plan_code, String, required: false

      argument :billing_anchor_date, GraphQL::Types::ISO8601Date, required: false
      argument :billing_time, Types::Contracts::BillingTimeEnum, required: false
      argument :ended_at, GraphQL::Types::ISO8601DateTime, required: false
      argument :started_at, GraphQL::Types::ISO8601DateTime, required: false

      argument :billing_entity_id, ID, required: false
      argument :consolidate_invoice, Boolean, required: false
      argument :payment_method, Types::PaymentMethods::ReferenceInput, required: false
      argument :purchase_order_number, String, required: false
    end
  end
end
