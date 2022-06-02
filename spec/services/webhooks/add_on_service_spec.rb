# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::AddOnService do
  subject(:webhook_add_on_service) { described_class.new(invoice) }

  let(:organization) { create(:organization, webhook_url: webhook_url) }
  let(:subscription) { create(:subscription, organization: organization) }
  let(:invoice) { create(:invoice, subscription: subscription) }
  let(:webhook_url) { 'http://foo.bar' }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post)
    end

    it 'calls the organization webhook url' do
      webhook_add_on_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_url)
      expect(lago_client).to have_received(:post)
    end

    it 'builds payload with invoice.add_on_added webhook type' do
      webhook_add_on_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_url)
      expect(lago_client).to have_received(:post) do |payload|
        expect(payload[:webhook_type]).to eq 'invoice.add_on_added'
      end
    end

    context 'without webhook_url' do
      let(:webhook_url) { nil }

      it 'does not call the organization webhook url' do
        webhook_add_on_service.call

        expect(LagoHttpClient::Client).not_to have_received(:new)
        expect(lago_client).not_to have_received(:post)
      end
    end
  end

  describe '.generate_headers' do
    let(:payload) do
      ::V1::InvoiceSerializer.new(
        invoice,
        root_name: 'invoice',
        includes: %i[customer subscription],
      ).serialize.merge(webook_type: 'add_on.created')
    end

    it 'generates the query headers' do
      headers = webhook_add_on_service.__send__(:generate_headers, payload)

      expect(headers).to include(have_key('X-Lago-Signature'))
    end

    it 'generates a correct signature' do
      signature = webhook_add_on_service.__send__(:generate_signature, payload)

      decoded_signature = JWT.decode(
        signature,
        RsaPublicKey,
        true,
        {
          algorithm: 'RS256',
          iss: ENV['LAGO_API_URL'],
          verify_iss: true,
        },
      ).first

      expect(decoded_signature['data']).to eq(payload.to_json)
    end
  end
end
