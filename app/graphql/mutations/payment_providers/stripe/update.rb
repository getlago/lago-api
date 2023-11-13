# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Stripe
      class Update < Base
        graphql_name 'UpdateStripePaymentProvider'
        description 'Update Stripe payment provider'

        argument :success_redirect_url, String, required: false
        argument :name, String, required: false

        type Types::PaymentProviders::Stripe
      end
    end
  end
end
