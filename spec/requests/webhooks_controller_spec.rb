# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhooksController, type: :request do
  describe 'POST /stripe' do
    let(:organization) { create(:organization) }

    let(:stripe_provider) do
      create(
        :stripe_provider,
        organization:,
        webhook_secret: 'secrests'
      )
    end

    let(:stripe_service) { instance_double(PaymentProviders::StripeService) }

    let(:event) do
      path = Rails.root.join('spec/fixtures/stripe/payment_intent_event.json')
      JSON.parse(File.read(path))
    end

    let(:result) do
      result = BaseService::Result.new
      result.event = Stripe::Event.construct_from(event)
      result
    end

    before do
      allow(PaymentProviders::Stripe::HandleIncomingWebhookService)
        .to receive(:call)
        .with(
          organization_id: organization.id,
          code: nil,
          body: event.to_json,
          signature: 'signature'
        )
        .and_return(result)
    end

    it 'handle stripe webhooks' do
      post(
        "/webhooks/stripe/#{stripe_provider.organization_id}",
        params: event.to_json,
        headers: {
          'HTTP_STRIPE_SIGNATURE' => 'signature',
          'Content-Type' => 'application/json'
        }
      )

      expect(response).to have_http_status(:success)
      expect(PaymentProviders::Stripe::HandleIncomingWebhookService)
        .to have_received(:call)
    end

    context 'when failing to handle stripe event' do
      let(:result) do
        BaseService::Result.new.service_failure!(code: 'webhook_error', message: 'Invalid payload')
      end

      it 'returns a bad request' do
        post(
          "/webhooks/stripe/#{stripe_provider.organization_id}",
          params: event.to_json,
          headers: {
            'HTTP_STRIPE_SIGNATURE' => 'signature',
            'Content-Type' => 'application/json'
          }
        )

        expect(response).to have_http_status(:bad_request)
        expect(PaymentProviders::Stripe::HandleIncomingWebhookService)
          .to have_received(:call)
      end
    end
  end

  describe 'POST /gocardless' do
    let(:organization) { create(:organization) }

    let(:gocardless_provider) do
      create(
        :gocardless_provider,
        organization:,
        webhook_secret: 'secrets'
      )
    end

    let(:gocardless_service) { instance_double(PaymentProviders::GocardlessService) }

    let(:events) do
      path = Rails.root.join('spec/fixtures/gocardless/events.json')
      JSON.parse(File.read(path))
    end

    let(:result) do
      result = BaseService::Result.new
      result.events = events['events'].map { |event| GoCardlessPro::Resources::Event.new(event) }
      result
    end

    before do
      allow(PaymentProviders::Gocardless::HandleIncomingWebhookService).to receive(:call)
        .with(
          organization_id: organization.id,
          code: nil,
          body: events.to_json,
          signature: 'signature'
        )
        .and_return(result)
    end

    it 'handle gocardless webhooks' do
      post(
        "/webhooks/gocardless/#{gocardless_provider.organization_id}",
        params: events.to_json,
        headers: {
          'Webhook-Signature' => 'signature',
          'Content-Type' => 'application/json'
        }
      )

      expect(response).to have_http_status(:success)

      expect(PaymentProviders::Gocardless::HandleIncomingWebhookService).to have_received(:call)
    end

    context 'when failing to handle gocardless event' do
      let(:result) do
        BaseService::Result.new.service_failure!(code: 'webhook_error', message: 'Invalid payload')
      end

      it 'returns a bad request' do
        post(
          "/webhooks/gocardless/#{gocardless_provider.organization_id}",
          params: events.to_json,
          headers: {
            'Webhook-Signature' => 'signature',
            'Content-Type' => 'application/json'
          }
        )

        expect(response).to have_http_status(:bad_request)

        expect(PaymentProviders::Gocardless::HandleIncomingWebhookService).to have_received(:call)
      end
    end
  end

  describe 'POST /adyen' do
    let(:organization) { create(:organization) }

    let(:adyen_provider) do
      create(:adyen_provider, organization:)
    end

    let(:body) do
      path = Rails.root.join('spec/fixtures/adyen/webhook_authorisation_response.json')
      JSON.parse(File.read(path))
    end

    let(:result) do
      result = BaseService::Result.new
      result.body = body
      result
    end

    before do
      allow(PaymentProviders::Adyen::HandleIncomingWebhookService).to receive(:call)
        .with(
          organization_id: organization.id,
          code: nil,
          body: body['notificationItems'].first&.dig('NotificationRequestItem')
        )
        .and_return(result)
    end

    it 'handle adyen webhooks' do
      post(
        "/webhooks/adyen/#{adyen_provider.organization_id}",
        params: body.to_json,
        headers: {
          'Content-Type' => 'application/json'
        }
      )

      expect(response).to have_http_status(:success)
      expect(PaymentProviders::Adyen::HandleIncomingWebhookService).to have_received(:call)
    end

    context 'when failing to handle adyen event' do
      let(:result) do
        BaseService::Result.new.service_failure!(code: 'webhook_error', message: 'Invalid payload')
      end

      it 'returns a bad request' do
        post(
          "/webhooks/adyen/#{adyen_provider.organization_id}",
          params: body.to_json,
          headers: {
            'Content-Type' => 'application/json'
          }
        )

        expect(response).to have_http_status(:bad_request)
        expect(PaymentProviders::Adyen::HandleIncomingWebhookService).to have_received(:call)
      end
    end
  end
end
