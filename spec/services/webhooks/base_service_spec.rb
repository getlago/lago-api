# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::BaseService, type: :service do
  subject(:webhook_service) { DummyClass.new(object:, webhook_id: previous_webhook&.id) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:object) { invoice }
  let(:previous_webhook) { nil }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:response) { OpenStruct.new(code: 200, body: 'Success') }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response).and_return(response)
    end

    context 'when organization has one webhook endpoint' do
      subject(:webhook_service) { DummyClass.new(object:) }

      it 'calls the webhook' do
        webhook_service.call

        expect(LagoHttpClient::Client).to have_received(:new)
          .with(organization.webhook_endpoints.first.webhook_url).once
        expect(lago_client).to have_received(:post_with_response).once
      end
    end

    context 'when organization has 2 webhook endpoints' do
      subject(:webhook_service) { DummyClass.new(object:) }

      let(:another_webhook_endpoint) { create(:webhook_endpoint, organization:) }

      it 'calls 2 webhooks' do
        webhook_service.call

        organization.reload.webhook_endpoints.each do |endpoint|
          expect(LagoHttpClient::Client).to have_received(:new).with(endpoint.webhook_url)
          expect(lago_client).to have_received(:post_with_response)
        end
      end
    end

    it 'builds payload with the object type root key' do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload['dummy']).to be_present
      end
    end

    it 'creates a succeeded webhook' do
      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first

      aggregate_failures do
        expect(webhook).to be_succeeded
        expect(webhook.retries).to be_zero
        expect(webhook.webhook_type).to eq('dummy.test')
        expect(webhook.endpoint).to eq(webhook.webhook_endpoint.webhook_url)
        expect(webhook.object_id).to eq(invoice.id)
        expect(webhook.object_type).to eq('Invoice')
        expect(webhook.http_status).to eq(200)
        expect(webhook.response).to eq('Success')
      end
    end

    context 'with a previous failed webhook' do
      let(:previous_webhook) do
        create(:webhook, :failed, webhook_endpoint: organization.webhook_endpoints.first)
      end

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

    context 'without webhook endpoint' do
      let(:organization) { create(:organization) }

      before do
        organization.webhook_endpoints.destroy_all
      end

      it 'does not call the webhook' do
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

      let(:webhook_endpoint) { organization.webhook_endpoints.first }

      before do
        allow(LagoHttpClient::Client).to receive(:new)
          .with(webhook_endpoint.webhook_url)
          .and_return(lago_client)
        allow(lago_client).to receive(:post_with_response)
          .and_raise(
            LagoHttpClient::HttpError.new(403, error_body.to_json, ''),
          )
      end

      it 'creates a failed webhook' do
        webhook_service.call

        webhook = Webhook.order(created_at: :desc).first

        aggregate_failures do
          expect(webhook).to be_failed
          expect(webhook.http_status).to eq(403)
        end
      end

      it 'enqueues a SendWebhookJob' do
        expect { webhook_service.call }.to have_enqueued_job(SendWebhookJob)
      end

      context 'with a previous failed webhook' do
        let(:previous_webhook) { create(:webhook, :failed, webhook_endpoint:) }

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
          let(:previous_webhook) { create(:webhook, :failed, webhook_endpoint:, retries: 2) }

          it 'does not enqueue a SendWebhookJob' do
            expect { webhook_service.call }.not_to have_enqueued_job(SendWebhookJob)
          end
        end
      end
    end

    context 'when request fails with a non HTTP error' do
      before do
        allow(LagoHttpClient::Client).to receive(:new)
          .with(organization.webhook_endpoints.first.webhook_url)
          .and_return(lago_client)
        allow(lago_client).to receive(:post_with_response)
          .and_raise(Net::ReadTimeout)
      end

      it 'creates a failed webhook' do
        webhook_service.call

        webhook = Webhook.order(created_at: :desc).first

        aggregate_failures do
          expect(webhook).to be_failed
          expect(webhook.http_status).to be_nil
          expect(webhook.response).to be_present
        end
      end

      it 'enqueues a SendWebhookJob' do
        expect { webhook_service.call }.to have_enqueued_job(SendWebhookJob)
      end
    end
  end

  describe '.generate_headers' do
    let(:webhook_endpoint) { create(:webhook_endpoint, organization:) }
    let(:payload) do
      ::V1::InvoiceSerializer.new(
        object,
        root_name: 'invoice',
        includes: %i[customer subscriptions],
      ).serialize.merge(webook_type: 'add_on.created')
    end

    it 'generates the query headers' do
      dummy_webhook_id = '895b41d0-474f-4a1f-a911-2df2d74dbe67'
      headers = webhook_service.__send__(:generate_headers, dummy_webhook_id, webhook_endpoint, payload)

      expect(headers).to have_key('X-Lago-Signature')
      expect(headers).to have_key('X-Lago-Signature-Algorithm')
      expect(headers).to have_key('X-Lago-Unique-Key')
      expect(headers['X-Lago-Signature-Algorithm']).to eq('jwt')
      expect(headers['X-Lago-Unique-Key']).to eq(dummy_webhook_id)
    end
  end

  describe '.jwt_signature' do
    let(:payload) do
      ::V1::InvoiceSerializer.new(
        object,
        root_name: 'invoice',
        includes: %i[customer subscriptions],
      ).serialize.merge(webook_type: 'add_on.created')
    end

    it 'generates a correct jwt signature' do
      signature = webhook_service.__send__(:jwt_signature, payload)

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

  describe '.hmac_signature' do
    let(:payload) do
      ::V1::InvoiceSerializer.new(
        object,
        root_name: 'invoice',
        includes: %i[customer subscriptions],
      ).serialize.merge(webook_type: 'add_on.created')
    end

    it 'generates a correct hmac signature' do
      signature = webhook_service.__send__(:hmac_signature, payload)
      hmac = OpenSSL::HMAC.digest('sha-256', organization.api_key, payload.to_json)
      base64_hmac = Base64.strict_encode64(hmac)

      expect(base64_hmac).to eq(signature)
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
