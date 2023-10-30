# frozen_string_literal: true

module Types
  module PaymentProviders
    class Stripe < Types::BaseObject
      graphql_name 'StripeProvider'

      field :id, ID, null: false
      field :secret_key, String, null: false

      field :create_customers, Boolean, null: false
      field :success_redirect_url, String, null: true

      # NOTE: Secret key is a sensitive information. It should not be sent back to the
      #       front end application. Instead we send an obfuscated value
      def secret_key
        "#{'•' * 8}…#{object.secret_key[-3..]}"
      end
    end
  end
end
