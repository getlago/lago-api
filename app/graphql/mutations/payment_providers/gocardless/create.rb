# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Mutations
  module PaymentProviders
    module Gocardless
      class Create < Base
        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "AddGocardlessPaymentProvider"
        description "Add or update Gocardless payment provider"

        input_object_class Types::PaymentProviders::GocardlessInput

        type Types::PaymentProviders::Gocardless
      end
    end
  end
end
