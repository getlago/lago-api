# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Gocardless
      class Update < Base
        graphql_name 'UpdateGocardlessPaymentProvider'
        description 'Update Gocardless payment provider'

        input_object_class Types::PaymentProviders::UpdateInput

        type Types::PaymentProviders::Gocardless
      end
    end
  end
end
