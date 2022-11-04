# frozen_string_literal: true

FactoryBot.define do
  factory :refund do
    credit_note
    payment
    association :payment_provider, factory: :stripe_provider
    association :payment_provider_customer, factory: :stripe_customer

    amount_cents { 200 }
    amount_currency { 'EUR' }
    provider_refund_id { SecureRandom.uuid }
    status { 'pending' }
  end
end
