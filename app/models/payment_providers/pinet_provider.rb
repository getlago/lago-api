# frozen_string_literal: true

module PaymentProviders
  class PinetProvider < BaseProvider
    validates :secret_key, presence: true
    validates :create_customers, inclusion: { in: [true, false] }
    validates :success_redirect_url, url: true, allow_nil: true, length: { maximum: 1024 }

    def secret_key=(secret_key)
      push_to_secrets(key: 'secret_key', value: secret_key)
    end

    def secret_key
      get_from_secrets('secret_key')
    end

    def create_customers=(value)
      push_to_settings(key: 'create_customers', value:)
    end

    def create_customers
      get_from_settings('create_customers')
    end

    def webhook_id=(value)
      push_to_settings(key: 'webhook_id', value:)
    end

    def webhook_id
      get_from_settings('webhook_id')
    end

    def key_id=(key_id)
      push_to_secrets(key: 'key_id', value: key_id)
    end

    def private_key=(private_key)
      push_to_secrets(key: 'private_key', value: private_key)
    end

    def key_id
      get_from_secrets('key_id')
    end

    def private_key
      get_from_secrets('private_key')
    end
  end
end
