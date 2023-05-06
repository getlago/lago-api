# frozen_string_literal: true

module Types
  module PaymentProviders
    class Adyen < Types::BaseObject
      graphql_name 'AdyenProvider'

      field :id, ID, null: false
      field :api_key, String, null: false
      field :merchant_account, String, null: false

      # NOTE: Api key is a sensitive information. It should not be sent back to the
      #       front end application. Instead we send an obfuscated value
      def api_key
        "#{'•' * 8}…#{object.api_key[-3..]}"
      end

      def merchant_account
        "#{'•' * 8}…#{object.api_key[-3..]}"
      end
    end
  end
end
