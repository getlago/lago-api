# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::IntegrationItems::FetchItems, type: :graphql do
  let(:required_permission) { 'organization:integrations:update' }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_item) { create(:integration_item, integration:) }
  let(:sync_service) { instance_double(Integrations::Aggregator::SyncService) }

  let(:items_response) do
    File.read(Rails.root.join('spec/fixtures/integration_aggregator/items_response.json'))
  end

  let(:mutation) do
    <<~GQL
      mutation($input: FetchIntegrationItemsInput!) {
        fetchIntegrationItems(input: $input) {
          collection { externalName, externalAccountCode, externalId }
        }
      }
    GQL
  end

  before do
    allow(Integrations::Aggregator::SyncService).to receive(:new).and_return(sync_service)
    allow(sync_service).to receive(:call).and_return(true)

    stub_request(:get, 'https://api.nango.dev/v1/netsuite/items?cursor=&limit=450')
      .to_return(status: 200, body: items_response, headers: {})

    integration_item
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'organization:integrations:update'

  it 'fetches the integration items' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {integrationId: integration.id},
      },
    )

    result_data = result['data']['fetchIntegrationItems']

    invoice_ids = result_data['collection'].map { |value| value['externalId'] }

    aggregate_failures do
      expect(invoice_ids).to eq(%w[755 745 753 484 828])
      expect(integration.integration_items.where(item_type: :standard).count).to eq(5)
    end
  end
end
