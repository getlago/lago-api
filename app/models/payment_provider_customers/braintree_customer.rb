# frozen_string_literal: true

module PaymentProviderCustomers
  class BraintreeCustomer < BaseCustomer
    PAYMENT_METHODS = %w[credit_card paypal].freeze

    validates :provider_payment_methods, presence: true
    validate :allowed_provider_payment_methods

    settings_accesors :payment_method_id, :payment_method_token

    def provider_payment_methods
      get_from_settings("provider_payment_methods", value: provider_payment_methods.to_a)
    end

    def provider_payment_methods=(provider_payment_methods)
      push_to_settings(key: "provider_payment_methods", value: provider_payment_methods.to_a)
    end

    private

    def allowed_provider_payment_methods
      return if (provider_payment_methods - PAYMENT_METHODS).blank?

      errors.add(:provider_payment_methods, :invalid)
    end
  end
end
