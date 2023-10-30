# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Gocardless
      class Update < Base
        graphql_name 'UpdateGocardlessPaymentProvider'
        description 'Update Gocardless payment provider'

        argument :success_redirect_url, String, required: false

        type Types::PaymentProviders::Gocardless
      end
    end
  end
end
