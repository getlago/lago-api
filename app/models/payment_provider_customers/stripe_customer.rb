# frozen_string_literal: true

module PaymentProviderCustomers
  class StripeCustomer < BaseCustomer
    PAYMENT_METHODS = %w[card sepa_debit us_bank_account bacs_debit].freeze

    validates :provider_payment_methods, presence: true
    validate :allowed_provider_payment_methods

    def payment_method_id
      get_from_settings("payment_method_id")
    end

    def payment_method_id=(payment_method_id)
      push_to_settings(key: "payment_method_id", value: payment_method_id)
    end

    def provider_payment_methods
      get_from_settings("provider_payment_methods")
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
