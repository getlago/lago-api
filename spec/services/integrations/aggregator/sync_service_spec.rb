# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::SyncService do
  subject(:sync_service) { described_class.new(integration:) }

  let(:integration) { create(:netsuite_integration) }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:sync_endpoint) { 'https://api.nango.dev/sync/start' }
    let(:syncs_list) do
      %w[
        netsuite-accounts-sync
        netsuite-items-sync
        netsuite-subsidiaries-sync
        netsuite-contacts-sync
      ]
    end

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(sync_endpoint)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)
    end

    it 'successfully calls sync endpoint' do
      sync_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(sync_endpoint)
      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload[:provider_config_key]).to eq('netsuite')
        expect(payload[:syncs]).to eq(syncs_list)
      end
    end
  end
end
