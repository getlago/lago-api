# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Stripe
      class Update < Base
        graphql_name 'UpdateStripePaymentProvider'
        description 'Update Stripe payment provider'

        input_object_class Types::PaymentProviders::UpdateInput

        type Types::PaymentProviders::Stripe
      end
    end
  end
end
