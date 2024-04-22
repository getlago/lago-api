# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::IntegrationItems::FetchTaxItems, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:sync_service) { instance_double(Integrations::Aggregator::SyncService) }

  let(:items_response) do
    File.read(Rails.root.join('spec/fixtures/integration_aggregator/tax_items_response.json'))
  end

  let(:mutation) do
    <<~GQL
      mutation($input: FetchIntegrationTaxItemsInput!) {
        fetchIntegrationTaxItems(input: $input) {
          collection { name, externalId }
        }
      }
    GQL
  end

  before do
    allow(Integrations::Aggregator::SyncService).to receive(:new).and_return(sync_service)
    allow(sync_service).to receive(:call).and_return(true)

    stub_request(:get, "https://api.nango.dev/v1/netsuite/taxitems?cursor=&limit=300")
      .to_return(status: 200, body: items_response, headers: {})

    IntegrationItem.destroy_all
  end

  it 'fetches the integration tax items' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: { integrationId: integration.id },
      },
    )

    result_data = result['data']['fetchIntegrationTaxItems']

    invoice_ids = result_data['collection'].map { |value| value['externalId'] }

    expect(invoice_ids).to eq(%w[-3557 -3879 -4692 -5307])
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: { integrationId: integration.id },
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: { integrationId: integration.id },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
