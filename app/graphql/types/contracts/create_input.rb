# frozen_string_literal: true

module Types
  module Contracts
    class CreateInput < BaseInputObject
      graphql_name "CreateContractInput"
      description "Create contract input arguments"

      argument :external_customer_id, String, required: true
      # Generated server-side when blank or omitted; see Mutations::Contracts::Create.
      argument :external_id, String, required: false
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
      # Payment settings: mirrors the subscription input; the payment method
      # scopes to the contract's customer.
      argument :payment_method, Types::PaymentMethods::ReferenceInput, required: false
    end
  end
end
