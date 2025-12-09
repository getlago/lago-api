# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Braintree
      class Update < Base
        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "UpdateBraintreePaymentProvider"
        description "Update Braintree payment provider"

        input_object_class Types::PaymentProviders::UpdateInput

        type Types::PaymentProviders::Braintree
      end
    end
  end
end
