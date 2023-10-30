# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Gocardless
      class Create < Base
        graphql_name 'AddGocardlessPaymentProvider'
        description 'Add or update Gocardless payment provider'

        input_object_class Types::PaymentProviders::GocardlessInput

        type Types::PaymentProviders::Gocardless
      end
    end
  end
end
