# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Invoices
    class RetryPaymentInput < BaseInputObject
      description "Retry payment input arguments"

      argument :id, ID, required: true
      argument :payment_method, Types::PaymentMethods::ReferenceInput, required: false
    end
  end
end
