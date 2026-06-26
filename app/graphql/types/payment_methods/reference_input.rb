# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module PaymentMethods
    class ReferenceInput < Types::BaseInputObject
      graphql_name "PaymentMethodReferenceInput"

      argument :payment_method_id, ID, required: false
      argument :payment_method_type, Types::PaymentMethods::MethodTypeEnum, required: false
    end
  end
end
