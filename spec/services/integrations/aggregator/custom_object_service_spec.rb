# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::CustomObjectService do
  subject(:custom_object_service) { described_class.new(integration:, name:) }

  let(:integration) { create(:hubspot_integration) }
  let(:name) { 'LagoInvoices' }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:endpoint) { 'https://api.nango.dev/v1/hubspot/custom-object' }

    let(:headers) do
      {
        'Connection-Id' => integration.connection_id,
        'Authorization' => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
        'Provider-Config-Key' => 'hubspot'
      }
    end

    let(:params) do
      {
        'name' => name
      }
    end

    let(:aggregator_response) do
      path = Rails.root.join('spec/fixtures/integration_aggregator/custom_object_response.json')
      JSON.parse(File.read(path))
    end

    before do
      allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
      allow(lago_client).to receive(:get).with(headers:, params:).and_return(aggregator_response)
    end

    it 'successfully fetches custom object' do
      result = custom_object_service.call
      custom_object = result.custom_object

      aggregate_failures do
        expect(LagoHttpClient::Client).to have_received(:new).with(endpoint)
        expect(lago_client).to have_received(:get)
        expect(custom_object.id).to eq('35482707')
        expect(custom_object.objectTypeId).to eq('2-35482707')
      end
    end
  end
end
