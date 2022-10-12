# frozen_string_literal: true

FactoryBot.define do
  factory :stripe_customer, class: 'PaymentProviderCustomers::StripeCustomer' do
    customer

    provider_customer_id { SecureRandom.uuid }
  end
end
