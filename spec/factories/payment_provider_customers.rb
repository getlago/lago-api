# frozen_string_literal: true

FactoryBot.define do
  factory :stripe_customer, class: "PaymentProviderCustomers::StripeCustomer" do
    customer

    provider_customer_id { SecureRandom.uuid }
    provider_payment_methods { %w[card sepa_debit] }
  end

  factory :gocardless_customer, class: "PaymentProviderCustomers::GocardlessCustomer" do
    customer

    provider_customer_id { SecureRandom.uuid }
  end

  factory :adyen_customer, class: "PaymentProviderCustomers::AdyenCustomer" do
    customer

    provider_customer_id { SecureRandom.uuid }
  end
end
