# frozen_string_literal: true

module Types
  module PaymentProviders
    class Stripe < Types::BaseObject
      graphql_name 'StripeProvider'

      field :id, ID, null: false
      field :secret_key, String, null: false

      field :create_customers, Boolean, null: false
      field :send_zero_amount_invoice, Boolean, null: false

      # NOTE: Secret key is a sensitive information. It should not be sent back to the
      #       front end application. Instead we send an obfuscated value
      def secret_key
        object.secret_key[0..2] + ('*' * 12)
      end
    end
  end
end
