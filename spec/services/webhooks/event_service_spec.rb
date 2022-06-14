# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::EventService do
  subject(:webhook_event_service) { described_class.new(object) }

  let(:organization) { create(:organization, webhook_url: webhook_url) }
  let(:webhook_url) { 'http://foo.bar' }
  let(:object) do
    {
      input_params: {
        customer_id: 'customer',
        transaction_id: SecureRandom.uuid,
        code: 'code'
      },
      error: 'Code does not exist',
      organization_id: organization.id
    }
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
      webhook_event_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_url)
      expect(lago_client).to have_received(:post)
    end

    it 'builds payload with event.error webhook type' do
      webhook_event_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_url)
      expect(lago_client).to have_received(:post) do |payload|
        expect(payload[:webhook_type]).to eq('event.error')
        expect(payload[:object_type]).to eq('event_error')
      end
    end

    context 'without webhook_url' do
      let(:webhook_url) { nil }

      it 'does not call the organization webhook url' do
        webhook_event_service.call

        expect(LagoHttpClient::Client).not_to have_received(:new)
        expect(lago_client).not_to have_received(:post)
      end
    end
  end

  describe '.generate_headers' do
    let(:payload) do
      ::ErrorSerializer.new(
        OpenStruct.new(object),
        root_name: 'error_event',
      ).serialize.merge(webhook_type: 'event.error')
    end

    it 'generates the query headers' do
      headers = webhook_event_service.__send__(:generate_headers, payload)

      expect(headers).to include(have_key('X-Lago-Signature'))
    end

    it 'generates a correct signature' do
      signature = webhook_event_service.__send__(:generate_signature, payload)

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
