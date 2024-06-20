# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::Integrations::AccountsResolver, type: :graphql do
  let(:required_permission) { 'organization:integrations:view' }
  let(:query) do
    <<~GQL
      query($integrationId: ID!) {
        integrationAccounts(integrationId: $integrationId) {
           collection { externalAccountCode externalId externalName }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:integration) { create(:xero_integration, organization:) }
  let(:lago_client) { instance_double(LagoHttpClient::Client) }
  let(:accounts_endpoint) { 'https://api.nango.dev/v1/xero/accounts' }

  let(:headers) do
    {
      'Connection-Id' => integration.connection_id,
      'Authorization' => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
      'Provider-Config-Key' => 'xero'
    }
  end

  let(:aggregator_response) do
    path = Rails.root.join('spec/fixtures/integration_aggregator/accounts_response.json')
    JSON.parse(File.read(path))
  end

  before do
    allow(LagoHttpClient::Client).to receive(:new).with(accounts_endpoint).and_return(lago_client)
    allow(lago_client).to receive(:get).with(headers:).and_return(aggregator_response)
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'organization:integrations:view'

  it 'returns a list of accounts' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {integrationId: integration.id}
    )

    accounts = result['data']['integrationAccounts']
    account = accounts['collection'].first

    aggregate_failures do
      expect(accounts['collection'].count).to eq(3)
      expect(account['externalAccountCode']).to eq('1111')
      expect(account['externalId']).to eq('12ec4c59-ad56-4a4f-93eb-fb0a7740f4e2')
      expect(account['externalName']).to eq('Accounts Payable')
    end
  end
end
