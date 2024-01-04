# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Pinet
      class Create < Base
        graphql_name 'AddPinetPaymentProvider'
        description 'Add Pinet API keys to the organization'

        input_object_class Types::PaymentProviders::PinetInput

        type Types::PaymentProviders::Pinet
      end
    end
  end
end
