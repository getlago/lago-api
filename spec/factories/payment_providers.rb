# frozen_string_literal: true

FactoryBot.define do
  factory :stripe_provider, class: 'PaymentProviders::StripeProvider' do
    organization
    type { 'PaymentProviders::StripeProvider' }

    secrets do
      { secret_key: SecureRandom.uuid }.to_json
    end

    settings do
      { create_customers: true, success_redirect_url:, error_redirect_url: }
    end

    transient do
      success_redirect_url { Faker::Internet.url }
      error_redirect_url { Faker::Internet.url }
    end
  end

  factory :gocardless_provider, class: 'PaymentProviders::GocardlessProvider' do
    organization
    type { 'PaymentProviders::GocardlessProvider' }

    secrets do
      { access_token: SecureRandom.uuid }.to_json
    end

    settings do
      { success_redirect_url: }
    end

    transient do
      success_redirect_url { Faker::Internet.url }
    end
  end

  factory :adyen_provider, class: 'PaymentProviders::AdyenProvider' do
    organization
    type { 'PaymentProviders::AdyenProvider' }

    secrets do
      { api_key:, hmac_key: }.to_json
    end

    settings do
      { live_prefix:, merchant_account:, success_redirect_url: }
    end

    transient do
      api_key { SecureRandom.uuid }
      merchant_account { Faker::Company.duns_number }
      live_prefix { Faker::Internet.domain_word }
      hmac_key { SecureRandom.uuid }
      success_redirect_url { Faker::Internet.url }
    end
  end
end
