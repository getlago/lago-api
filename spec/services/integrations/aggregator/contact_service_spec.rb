# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::ContactService do
  subject(:contact_service) { described_class.new(integration:, id:) }

  let(:integration) { create(:netsuite_integration) }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:contact_endpoint) { "https://api.nango.dev/v1/netsuite/contacts/#{id}" }
    let(:id) { '6017' }
    let(:headers) do
      {
        'Connection-Id' => integration.connection_id,
        'Authorization' => "Bearer #{ENV['NANGO_SECRET_KEY']}",
        'Provider-Config-Key' => 'netsuite',
      }
    end

    let(:aggregator_response) do
      path = Rails.root.join('spec/fixtures/integration_aggregator/contact_response.json')
      JSON.parse(File.read(path))
    end

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(contact_endpoint)
        .and_return(lago_client)
      allow(lago_client).to receive(:get)
        .with(headers:)
        .and_return(aggregator_response)
    end

    it 'successfully fetches contact' do
      result = contact_service.call

      aggregate_failures do
        expect(LagoHttpClient::Client).to have_received(:new).with(contact_endpoint)
        expect(lago_client).to have_received(:get)
        expect(result.contact.subsidiary_id).to eq('1')
      end
    end
  end
end
