# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Paystack
      class Update < Base
        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "UpdatePaystackPaymentProvider"
        description "Update Paystack payment provider"

        input_object_class Types::PaymentProviders::PaystackUpdateInput

        type Types::PaymentProviders::Paystack
      end
    end
  end
end
