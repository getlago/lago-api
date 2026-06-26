# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Mutations
  module PaymentProviders
    module Gocardless
      class Update < Base
        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "UpdateGocardlessPaymentProvider"
        description "Update Gocardless payment provider"

        input_object_class Types::PaymentProviders::UpdateInput

        type Types::PaymentProviders::Gocardless
      end
    end
  end
end
