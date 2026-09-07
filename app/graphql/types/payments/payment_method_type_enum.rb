# frozen_string_literal: true

module Types
  module Payments
    class PaymentMethodTypeEnum < Types::BaseEnum
      # PaymentMethodTypeEnum already represents manual/provider payment methods.
      graphql_name "PaymentProviderMethodTypeEnum"

      PaymentMethod::PROVIDER_METHOD_TYPES.each do |type|
        value type
      end
    end
  end
end
