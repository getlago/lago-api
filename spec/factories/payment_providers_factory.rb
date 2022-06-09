# frozen_string_literal: true

FactoryBot.define do
  factory :stripe_provider, class: 'PaymentProviders::StripeProvider' do
    organization
    type { 'PaymentProviders::StripeProvider' }
    settings { {} }

    secrets do
      { public_key: SecureRandom.uuid, secret_key: SecureRandom.uuid }.to_json
    end
  end
end
