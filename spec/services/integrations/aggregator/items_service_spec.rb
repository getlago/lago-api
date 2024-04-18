# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::ItemsService do
  subject(:items_service) { described_class.new(integration:) }

  let(:integration) { create(:netsuite_integration) }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:items_endpoint) { 'https://api.nango.dev/v1/netsuite/items' }
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
      path = Rails.root.join('spec/fixtures/integration_aggregator/items_response.json')
      JSON.parse(File.read(path))
    end

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(items_endpoint)
        .and_return(lago_client)
      allow(lago_client).to receive(:get)
        .with(headers:, params:)
        .and_return(aggregator_response)
    end

    it 'successfully fetches items' do
      result = items_service.call

      aggregate_failures do
        expect(LagoHttpClient::Client).to have_received(:new).with(items_endpoint)
        expect(lago_client).to have_received(:get)
        expect(result.items.pluck('id')).to eq(%w[755 745 753 484 828])
      end
    end
  end
end
