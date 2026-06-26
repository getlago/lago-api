# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Mutations
  module PaymentProviders
    module Moneyhash
      class Create < Base
        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "AddMoneyhashPaymentProvider"
        description "Add Moneyhash payment provider"

        input_object_class Types::PaymentProviders::MoneyhashInput

        type Types::PaymentProviders::Moneyhash
      end
    end
  end
end
