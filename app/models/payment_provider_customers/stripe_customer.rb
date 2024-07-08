# frozen_string_literal: true

module PaymentProviderCustomers
  class StripeCustomer < BaseCustomer
    PAYMENT_METHODS = %w[card sepa_debit us_bank_account bacs_debit link].freeze

    validates :provider_payment_methods, presence: true
    validate :allowed_provider_payment_methods
    validate :link_payment_method_can_exist_only_with_card

    settings_accessors :payment_method_id

    def provider_payment_methods
      get_from_settings('provider_payment_methods')
    end

    def provider_payment_methods=(provider_payment_methods)
      push_to_settings(key: 'provider_payment_methods', value: provider_payment_methods.to_a)
    end

    private

    def allowed_provider_payment_methods
      return if (provider_payment_methods - PAYMENT_METHODS).blank?

      errors.add(:provider_payment_methods, :invalid)
    end

    def link_payment_method_can_exist_only_with_card
      return if provider_payment_methods.exclude?('link') || provider_payment_methods.include?('card')

      errors.add(:provider_payment_methods, :invalid)
    end
  end
end
