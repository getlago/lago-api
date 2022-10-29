# frozen_string_literal: true

module PaymentProviders
  class StripeProvider < BaseProvider
    validates :secret_key, presence: true

    validates :create_customers, inclusion: { in: [true, false] }

    def secret_key=(secret_key)
      push_to_secrets(key: 'secret_key', value: secret_key)
    end

    def secret_key
      get_from_secrets('secret_key')
    end

    def create_customers=(value)
      push_to_settings(key: 'create_customers', value: value)
    end

    def create_customers
      get_from_settings('create_customers')
    end

    def webhook_id=(value)
      push_to_settings(key: 'webhook_id', value: value)
    end

    def webhook_id
      get_from_settings('webhook_id')
    end
  end
end
