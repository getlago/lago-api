# frozen_string_literal: true

module PaymentProviders
  class AdyenProvider < BaseProvider
    validates :api_key, :merchant_account, presence: true

    def environment
      if Rails.env.production? && live_prefix.present?
        :live
      else
        :test
      end
    end

    def api_key=(value)
      push_to_secrets(key: 'api_key', value:)
    end

    def api_key
      get_from_secrets('api_key')
    end

    def merchant_account=(value)
      push_to_secrets(key: 'merchant_account', value:)
    end

    def merchant_account
      get_from_secrets('merchant_account')
    end

    def live_prefix=(value)
      push_to_secrets(key: 'live_prefix', value:)
    end

    def live_prefix
      get_from_secrets('live_prefix')
    end

    def hmac_key=(value)
      push_to_secrets(key: 'hmac_key', value:)
    end

    def hmac_key
      get_from_secrets('hmac_key')
    end
  end
end
