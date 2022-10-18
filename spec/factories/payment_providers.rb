# frozen_string_literal: true

FactoryBot.define do
  factory :stripe_provider, class: 'PaymentProviders::StripeProvider' do
    organization
    type { 'PaymentProviders::StripeProvider' }

    secrets do
      { secret_key: SecureRandom.uuid }.to_json
    end

    settings do
      { create_customers: true }
    end
  end

  factory :gocardless_provider, class: 'PaymentProviders::GocardlessProvider' do
    organization
    type { 'PaymentProviders::GocardlessProvider' }

    secrets do
      { access_token: SecureRandom.uuid }.to_json
    end
  end
end
