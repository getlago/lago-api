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

    trait :requires_action do
      status { 'requires_action' }
      provider_payment_data do
        {
          redirect_to_url: {url: 'https://foo.bar'}
        }
      end
    end
  end
end
