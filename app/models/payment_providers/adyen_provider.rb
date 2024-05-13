# frozen_string_literal: true

module PaymentProviders
  class AdyenProvider < BaseProvider
    SUCCESS_REDIRECT_URL = 'https://www.adyen.com/'

    validates :api_key, :merchant_account, presence: true
    validates :success_redirect_url, adyen_url: true, allow_nil: true, length: {maximum: 1024}

    settings_accessors :live_prefix, :merchant_account
    secrets_accessors :api_key, :hmac_key

    def environment
      if Rails.env.production? && live_prefix.present?
        :live
      else
        :test
      end
    end
  end
end
