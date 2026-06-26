# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Payments
    class CreateInput < Types::BaseInputObject
      graphql_name "CreatePaymentInput"

      argument :amount_cents, GraphQL::Types::BigInt, required: true
      argument :created_at, GraphQL::Types::ISO8601DateTime, required: true
      argument :invoice_id, ID, required: true
      argument :reference, String, required: true
    end
  end
end
