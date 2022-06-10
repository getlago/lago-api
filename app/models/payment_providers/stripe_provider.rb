# frozen_string_literal: true

module PaymentProviders
  class StripeProvider < BaseProvider
    validates :public_key, presence: true
    validates :secret_key, presence: true

    validates :create_customers, inclusion: { in: [true, false] }
    validates :send_zero_amount_invoice, inclusion: { in: [true, false] }

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

    def create_customers=(value)
      push_to_settings(key: 'create_customers', value: value)
    end

    def create_customers
      get_from_settings('create_customers')
    end

    def send_zero_amount_invoice=(value)
      push_to_settings(key: 'send_zero_amount_invoice', value: value)
    end

    def send_zero_amount_invoice
      get_from_settings('send_zero_amount_invoice')
    end
  end
end
