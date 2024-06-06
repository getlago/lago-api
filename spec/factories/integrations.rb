# frozen_string_literal: true

FactoryBot.define do
  factory :netsuite_integration, class: 'Integrations::NetsuiteIntegration' do
    organization
    type { 'Integrations::NetsuiteIntegration' }
    code { "netsuite_#{SecureRandom.uuid}" }
    name { 'Accounting integration 1' }

    secrets do
      {connection_id: SecureRandom.uuid, client_secret: SecureRandom.uuid}.to_json
    end

    settings do
      {account_id: 'acc_12345', client_id: 'cli_12345', script_endpoint_url: Faker::Internet.url}
    end
  end

  factory :okta_integration, class: 'Integrations::OktaIntegration' do
    organization
    type { 'Integrations::OktaIntegration' }
    code { 'okta' }
    name { 'Okta Integration' }

    settings do
      {client_id: SecureRandom.uuid, domain: 'foo.test', organization_name: 'Foobar'}
    end

    secrets do
      {client_secret: SecureRandom.uuid}.to_json
    end
  end

  factory :anrok_integration, class: 'Integrations::AnrokIntegration' do
    organization
    type { 'Integrations::AnrokIntegration' }
    code { 'anrok' }
    name { 'Anrok Integration' }

    secrets do
      {api_key: SecureRandom.uuid}.to_json
    end
  end

  factory :xero_integration, class: 'Integrations::XeroIntegration' do
    organization
    type { 'Integrations::XeroIntegration' }
    code { 'xero' }
    name { 'Xero Integration' }
  end
end
