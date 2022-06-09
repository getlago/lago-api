# frozen_string_literal: true

FactoryBot.define do
  factory :stripe_provider, class: 'PaymentProviders::StripeProvider' do
    organization
    type { 'PaymentProviders::StripeProvider' }
    properties { {} }

    secrets do
      { api_key: SecureRandom.uuid, api_secret: SecureRandom.uuid }.to_json
    end
  end
end
