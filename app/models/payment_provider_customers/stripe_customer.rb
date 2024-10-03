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

# == Schema Information
#
# Table name: payment_provider_customers
#
#  id                   :uuid             not null, primary key
#  settings             :jsonb            not null
#  type                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  customer_id          :uuid             not null
#  payment_provider_id  :uuid
#  provider_customer_id :string
#
# Indexes
#
#  index_payment_provider_customers_on_customer_id_and_type  (customer_id,type) UNIQUE
#  index_payment_provider_customers_on_payment_provider_id   (payment_provider_id)
#  index_payment_provider_customers_on_provider_customer_id  (provider_customer_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (payment_provider_id => payment_providers.id)
#
