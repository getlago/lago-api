# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::SendPrivateAppTokenService do
  subject(:send_private_token_service) { described_class.new(integration:) }

  let(:integration) { create(:hubspot_integration) }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:endpoint) { "https://api.nango.dev/connection/#{integration.connection_id}/metadata" }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(endpoint)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)

      integration.private_app_token = 'privatetoken'
      integration.save!
    end

    it 'successfully sends token to hubspot' do
      send_private_token_service.call

      aggregate_failures do
        expect(LagoHttpClient::Client).to have_received(:new)
          .with(endpoint)
        expect(lago_client).to have_received(:post_with_response) do |payload|
          expect(payload[:privateAppToken]).to eq('privatetoken')
        end
      end
    end
  end
end
