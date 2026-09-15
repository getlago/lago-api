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

      # Billing entity: when omitted the contract inherits the customer's.
      argument :billing_entity_id, ID, required: false
      # Invoicing settings.
      argument :consolidate_invoice, Boolean, required: false
      argument :purchase_order_number, String, required: false
      # Payment settings: payment_method scopes to the contract's customer.
      argument :payment_method_id, ID, required: false
      argument :payment_method_type, Types::PaymentMethods::MethodTypeEnum, required: false
    end
  end
end
