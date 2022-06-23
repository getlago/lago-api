# frozen_string_literal: true

FactoryBot.define do
  factory :payment do
    invoice
    payment_provider
    payment_provider_customer

    amount_cents { 200 }
    amount_currency { 'EUR' }
    provider_payment_id { SecureRandom.uuid }
    status { 'pending' }
  end
end
