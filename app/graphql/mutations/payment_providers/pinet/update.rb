# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Pinet
      class Update < Base
        graphql_name 'UpdatePinetPaymentProvider'
        description 'Update Pinet payment provider'

        argument :success_redirect_url, String, required: false

        type Types::PaymentProviders::Pinet
      end
    end
  end
end
