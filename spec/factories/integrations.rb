# frozen_string_literal: true

FactoryBot.define do
  factory :netsuite_integration, class: 'Integrations::NetsuiteIntegration' do
    organization
    type { 'Integrations::NetsuiteIntegration' }
    code { "netsuite_#{SecureRandom.uuid}" }
    name { 'Accounting integration 1' }

    secrets do
      { connection_id: SecureRandom.uuid, client_secret: SecureRandom.uuid }.to_json
    end

    settings do
      { account_id: 'acc_12345', client_id: 'cli_12345', script_endpoint_url: Faker::Internet.url }
    end
  end
end
