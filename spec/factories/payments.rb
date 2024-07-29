# frozen_string_literal: true

FactoryBot.define do
  factory :payment do
    association :payable, factory: :invoice
    association :payment_provider, factory: :stripe_provider
    association :payment_provider_customer, factory: :stripe_customer

    amount_cents { 200 }
    amount_currency { 'EUR' }
    provider_payment_id { SecureRandom.uuid }
    status { 'pending' }
  end
end
