# frozen_string_literal: true

module PaymentProviders
  class StripeProvider < BaseProvider
    validates :api, presence: true


    def public_key=(public_key)
      push_to_secrets(key: 'public_key', value: public_key)
    end

    def public_key
      get_from_secrets('public_key')
    end

    def secret_key=(secret_key)
      push_to_secrets(key: 'secret_key', value: secret_key)
    end

    def secret_key
      get_from_secrets('secret_key')
    end
  end
end
