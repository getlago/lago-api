# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::TaxItemsService do
  subject(:tax_items_service) { described_class.new(integration:) }

  let(:integration) { create(:netsuite_integration) }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:tax_items_endpoint) { 'https://api.nango.dev/v1/netsuite/taxitems' }
    let(:headers) do
      {
        'Connection-Id' => integration.connection_id,
        'Authorization' => 'Bearer ',
        'Provider-Config-Key' => 'netsuite',
      }
    end
    let(:params) do
      {
        limit: 300,
        cursor: '',
      }
    end

    let(:aggregator_response) do
      path = Rails.root.join('spec/fixtures/integration_aggregator/tax_items_response.json')
      JSON.parse(File.read(path))
    end

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(tax_items_endpoint)
        .and_return(lago_client)
      allow(lago_client).to receive(:get)
        .with(headers:, params:)
        .and_return(aggregator_response)

      IntegrationItem.destroy_all
    end

    it 'successfully fetches tax items' do
      result = tax_items_service.call

      aggregate_failures do
        expect(LagoHttpClient::Client).to have_received(:new).with(tax_items_endpoint)
        expect(lago_client).to have_received(:get)
        expect(result.tax_items.pluck('id')).to eq(%w[-3557 -3879 -4692 -5307])
        expect(IntegrationItem.count).to eq(4)
        expect(IntegrationItem.first.item_type).to eq('tax')
      end
    end
  end
end
