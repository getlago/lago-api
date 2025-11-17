# frozen_string_literal: true

module Types
  module PaymentMethods
    class ReferenceObject < Types::BaseObject
      graphql_name "PaymentMethodReferenceObject"

      field :payment_method_id, ID
      field :payment_method_type, Types::PaymentMethods::MethodTypeEnum
    end
  end
end
