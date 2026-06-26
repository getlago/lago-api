# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Mutations
  module PaymentProviders
    module Cashfree
      class Update < Base
        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "UpdateCashfreePaymentProvider"
        description "Update Cashfree payment provider"

        input_object_class Types::PaymentProviders::UpdateInput

        type Types::PaymentProviders::Cashfree
      end
    end
  end
end
