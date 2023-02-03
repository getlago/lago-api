# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::InvoicesService do
  subject(:webhook_invoice_service) { described_class.new(invoice) }

  let(:organization) { create(:organization, webhook_url:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:webhook_url) { 'http://foo.bar' }

  before do
    create_list(:fee, 4, invoice:)
    create_list(:credit, 4, invoice:)
  end

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post)
    end

    it 'calls the organization webhook url' do
      webhook_invoice_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_url)
      expect(lago_client).to have_received(:post)
    end

    it 'builds payload with invoice.created webhook type' do
      webhook_invoice_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_url)
      expect(lago_client).to have_received(:post) do |payload|
        expect(payload[:webhook_type]).to eq('invoice.created')
        expect(payload[:object_type]).to eq('invoice')
      end
    end

    it 'builds payload with the object type root key' do
      webhook_invoice_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_url)
      expect(lago_client).to have_received(:post) do |payload|
        expect(payload['invoice']).to be_present
      end
    end

    context 'without webhook_url' do
      let(:webhook_url) { nil }

      it 'does not call the organization webhook url' do
        webhook_invoice_service.call

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
        includes: %i[customer subscription fees],
      ).serialize.merge(webook_type: 'invoice.created')
    end

    it 'generates the query headers' do
      headers = webhook_invoice_service.__send__(:generate_headers, payload)

      expect(headers).to include(have_key('X-Lago-Signature'))
    end

    it 'generates a correct signature' do
      signature = webhook_invoice_service.__send__(:generate_signature, payload)

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
