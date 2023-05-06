# frozen_string_literal: true

module PaymentProviders
  class AdyenProvider < BaseProvider
    validates :api_key, presence: true

    def environment
      if Rails.env.production?
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
  end
end
