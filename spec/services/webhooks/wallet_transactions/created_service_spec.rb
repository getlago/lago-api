# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::WalletTransactions::CreatedService do
  subject(:webhook_service) { described_class.new(object: wallet_transaction) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:wallet_transaction) { create(:wallet_transaction, wallet:) }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)
    end

    it 'builds payload with wallet_transaction.created webhook type' do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_endpoints.first.webhook_url)

      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload[:webhook_type]).to eq('wallet_transaction.created')
        expect(payload[:object_type]).to eq('wallet_transaction')
      end
    end
  end
end
