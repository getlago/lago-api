# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Braintree
      class Create < Base
        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "AddBraintreePaymentProvider"
        description "Add Braintree payment prodiver"

        input_object_class Types::PaymentProviders::BraintreeInput

        type Types::PaymentProviders::Braintree
      end
    end
  end
end
