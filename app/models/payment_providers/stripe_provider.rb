# frozen_string_literal: true

module PaymentProviders
  class StripeProvider < BaseProvider
    SUCCESS_REDIRECT_URL = 'https://stripe.com/'

    validates :secret_key, presence: true
    validates :success_redirect_url, url: true, allow_nil: true, length: { maximum: 1024 }

    def secret_key=(secret_key)
      push_to_secrets(key: 'secret_key', value: secret_key)
    end

    def secret_key
      get_from_secrets('secret_key')
    end

    def webhook_id=(value)
      push_to_settings(key: 'webhook_id', value:)
    end

    def webhook_id
      get_from_settings('webhook_id')
    end
  end
end
