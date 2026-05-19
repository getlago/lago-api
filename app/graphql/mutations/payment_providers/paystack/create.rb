# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Paystack
      class Create < Base
        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "AddPaystackPaymentProvider"
        description "Add Paystack payment provider"

        input_object_class Types::PaymentProviders::PaystackInput

        type Types::PaymentProviders::Paystack
      end
    end
  end
end
