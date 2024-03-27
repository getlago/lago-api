# frozen_string_literal: true

module Types
  module PaymentProviders
    class Adyen < Types::BaseObject
      graphql_name "AdyenProvider"

      field :api_key, String, null: true
      field :code, String, null: false
      field :hmac_key, String, null: true
      field :id, ID, null: false
      field :live_prefix, String, null: true
      field :merchant_account, String, null: false
      field :name, String, null: false
      field :success_redirect_url, String, null: true

      # NOTE: Api key is a sensitive information. It should not be sent back to the
      #       front end application. Instead we send an obfuscated value
      def api_key
        "#{"•" * 8}…#{object.api_key[-3..]}"
      end

      def hmac_key
        "#{"•" * 8}…#{object.hmac_key[-3..]}" if object.hmac_key.present?
      end
    end
  end
end
