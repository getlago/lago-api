# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Adyen
      class Update < Base
        graphql_name 'UpdateAdyenPaymentProvider'
        description 'Update Adyen payment provider'

        argument :success_redirect_url, String, required: false

        type Types::PaymentProviders::Adyen
      end
    end
  end
end
