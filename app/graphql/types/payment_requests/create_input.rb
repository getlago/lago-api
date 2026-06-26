# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module PaymentRequests
    class CreateInput < Types::BaseInputObject
      graphql_name "PaymentRequestCreateInput"

      argument :external_customer_id, String, required: true

      argument :email, String, required: false
      argument :lago_invoice_ids, [String], required: false
      argument :payment_method, Types::PaymentMethods::ReferenceInput, required: false
    end
  end
end
