# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhooksController, type: :request do
  describe 'POST /stripe' do
    let(:organization) { create(:organization) }

    let(:stripe_provider) do
      create(
        :stripe_provider,
        organization: organization,
        webhook_secret: 'secrests',
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
      allow(PaymentProviders::StripeService).to receive(:new)
        .and_return(stripe_service)
      allow(stripe_service).to receive(:handle_incoming_webhook)
        .with(
          organization_id: organization.id,
          params: event.to_json,
          signature: 'signature',
        )
        .and_return(result)
    end

    it 'handle stripe webhooks' do
      post(
        "/webhooks/stripe/#{stripe_provider.organization_id}",
        params: event.to_json,
        headers: {
          'HTTP_STRIPE_SIGNATURE' => 'signature',
          'Content-Type' => 'application/json',
        },
      )

      expect(response).to have_http_status(:success)

      expect(PaymentProviders::StripeService).to have_received(:new)
      expect(stripe_service).to have_received(:handle_incoming_webhook)
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
            'Content-Type' => 'application/json',
          },
        )

        expect(response).to have_http_status(:bad_request)

        expect(PaymentProviders::StripeService).to have_received(:new)
        expect(stripe_service).to have_received(:handle_incoming_webhook)
      end
    end
  end
end
