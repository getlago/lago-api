# frozen_string_literal: true

module PaymentProviders
  class StripeProvider < BaseProvider
    SUCCESS_REDIRECT_URL = 'https://stripe.com/'

    validates :secret_key, presence: true
    validates :success_redirect_url, url: true, allow_nil: true, length: { maximum: 1024 }

    settings_accessors :webhook_id
    secrets_accessors :secret_key
  end
end
