# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::BaseService, type: :service do
  subject(:webhook_service) { DummyClass.new(object:, webhook_id: previous_webhook&.id) }

  let(:organization) { create(:organization, webhook_url:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:webhook_url) { 'http://foo.bar' }
  let(:object) { invoice }
  let(:previous_webhook) { nil }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:response) { OpenStruct.new(code: 200, body: 'Success') }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response).and_return(response)
    end

    it 'calls the organization webhook url' do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_url)
      expect(lago_client).to have_received(:post_with_response)
    end

    it 'builds payload with the object type root key' do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_url)
      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload['dummy']).to be_present
      end
    end

    it 'creates a succeeded webhook' do
      webhook_service.call

      webhook = Webhook.first

      aggregate_failures do
        expect(webhook).to be_succeeded
        expect(webhook.retries).to be_zero
        expect(webhook.webhook_type).to eq('dummy.test')
        expect(webhook.endpoint).to eq(organization.webhook_url)
        expect(webhook.object_id).to eq(invoice.id)
        expect(webhook.object_type).to eq('Invoice')
        expect(webhook.http_status).to eq(200)
        expect(webhook.response).to eq('Success')
      end
    end

    context 'with a previous failed webhook' do
      let(:previous_webhook) { create(:webhook, :failed, organization:, endpoint: webhook_url) }

      it 'succeeds the retried webhook' do
        webhook_service.call

        previous_webhook.reload

        aggregate_failures do
          expect(previous_webhook).to be_succeeded
          expect(previous_webhook.http_status).to eq(200)
          expect(previous_webhook.retries).to eq(1)
          expect(previous_webhook.last_retried_at).not_to be_nil
        end
      end
    end

    context 'without webhook_url' do
      let(:webhook_url) { nil }

      it 'does not call the organization webhook url' do
        webhook_service.call

        expect(LagoHttpClient::Client).not_to have_received(:new)
        expect(lago_client).not_to have_received(:post_with_response)
      end
    end

    context 'when client returns an error' do
      let(:error_body) do
        {
          message: 'forbidden',
        }
      end

      before do
        allow(LagoHttpClient::Client).to receive(:new)
          .with(organization.webhook_url)
          .and_return(lago_client)
        allow(lago_client).to receive(:post_with_response)
          .and_raise(
            LagoHttpClient::HttpError.new(403, error_body.to_json, ''),
          )
      end

      it 'creates a failed webhook' do
        webhook_service.call

        webhook = Webhook.first

        aggregate_failures do
          expect(webhook).to be_failed
          expect(webhook.http_status).to eq(403)
        end
      end

      it 'enqueues a SendWebhookJob' do
        expect { webhook_service.call }.to have_enqueued_job(SendWebhookJob)
      end

      context 'with a previous failed webhook' do
        let(:previous_webhook) { create(:webhook, :failed, organization:, endpoint: webhook_url) }

        it 'fails the retried webhooks' do
          webhook_service.call

          previous_webhook.reload

          aggregate_failures do
            expect(previous_webhook).to be_failed
            expect(previous_webhook.http_status).to eq(403)
            expect(previous_webhook.retries).to eq(1)
            expect(previous_webhook.last_retried_at).not_to be_nil
          end
        end

        context 'when the previous failed webhook have been retried 3 times' do
          let(:previous_webhook) { create(:webhook, :failed, organization:, retries: 2, endpoint: webhook_url) }

          it 'does not enqueue a SendWebhookJob' do
            expect { webhook_service.call }.not_to have_enqueued_job(SendWebhookJob)
          end
        end
      end
    end
  end

  describe '.generate_headers' do
    let(:payload) do
      ::V1::InvoiceSerializer.new(
        object,
        root_name: 'invoice',
        includes: %i[customer subscriptions],
      ).serialize.merge(webook_type: 'add_on.created')
    end

    it 'generates the query headers' do
      headers = webhook_service.__send__(:generate_headers, payload)

      expect(headers).to include(have_key('X-Lago-Signature'))
    end

    it 'generates a correct signature' do
      signature = webhook_service.__send__(:generate_signature, payload)

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

class DummyClass < Webhooks::BaseService
  def current_organization
    @current_organization ||= object.organization
  end

  def object_serializer
    ::V1::InvoiceSerializer.new(
      object,
      root_name: 'invoice',
    )
  end

  def webhook_type
    'dummy.test'
  end

  def object_type
    'dummy'
  end
end
