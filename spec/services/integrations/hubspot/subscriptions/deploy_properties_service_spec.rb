# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Hubspot::Subscriptions::DeployPropertiesService do
  subject(:deploy_properties_service) { described_class.new(integration:) }

  let(:integration) { create(:hubspot_integration) }

  describe '.call' do
    let(:http_client) { instance_double(LagoHttpClient::Client) }
    let(:endpoint) { "https://api.nango.dev/v1/hubspot/properties" }
    let(:response) { instance_double('Response', success?: true) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(endpoint)
        .and_return(http_client)
      allow(http_client).to receive(:post_with_response).and_return(response)

      integration.subscriptions_properties_version = nil
      integration.save!
    end

    it 'successfully deploys subscriptions properties and updates the subscriptions_properties_version' do
      deploy_properties_service.call

      aggregate_failures do
        expect(LagoHttpClient::Client).to have_received(:new).with(endpoint)
        expect(http_client).to have_received(:post_with_response) do |payload, headers|
          expect(payload[:objectType]).to eq('LagoSubscriptions')
          expect(headers['Authorization']).to include('Bearer')
        end
        expect(integration.reload.subscriptions_properties_version).to eq(described_class::VERSION)
      end
    end

    context 'when subscriptions_properties_version is already up-to-date' do
      before do
        integration.subscriptions_properties_version = described_class::VERSION
        integration.save!
      end

      it 'does not make an API call and keeps the version unchanged' do
        deploy_properties_service.call

        aggregate_failures do
          expect(LagoHttpClient::Client).not_to have_received(:new)
          expect(http_client).not_to have_received(:post_with_response)
          expect(integration.reload.subscriptions_properties_version).to eq(described_class::VERSION)
        end
      end
    end
  end
end
