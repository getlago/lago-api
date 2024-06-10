# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::Stripe::RegisterWebhookService do
  subject(:provider_service) { described_class.new(payment_provider) }

  let(:organization) { create(:organization) }
  let(:payment_provider) { create(:stripe_provider, organization:) }

  describe '.call' do
    let(:stripe_webhook) do
      ::Stripe::WebhookEndpoint.construct_from(
        id: 'we_123456',
        secret: 'whsec_123456'
      )
    end

    before do
      allow(::Stripe::WebhookEndpoint)
        .to receive(:create)
        .and_return(stripe_webhook)
    end

    it 'registers a webhook on stripe' do
      result = provider_service.call

      expect(result).to be_success

      aggregate_failures do
        expect(result.payment_provider.webhook_id).to eq('we_123456')
        expect(result.payment_provider.webhook_secret).to eq('whsec_123456')
      end
    end

    context 'when authentication fails on stripe API' do
      before do
        allow(::Stripe::WebhookEndpoint)
          .to receive(:create)
          .and_raise(::Stripe::AuthenticationError.new(
            'This API call cannot be made with a publishable API key. Please use a secret API key. You can find a list of your API keys at https://dashboard.stripe.com/account/apikeys.'
          ))
      end

      it 'delivers an error webhook' do
        result = provider_service.call

        expect(result).to be_success

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            'payment_provider.error',
            payment_provider,
            provider_error: {
              source: 'stripe',
              action: 'payment_provider.register_webhook',
              message: 'This API call cannot be made with a publishable API key. Please use a secret API key. You can find a list of your API keys at https://dashboard.stripe.com/account/apikeys.',
              code: nil
            }
          )
      end
    end

    context 'when the webhook limit is reached' do
      before do
        allow(::Stripe::WebhookEndpoint)
          .to receive(:create)
          .and_raise(::Stripe::InvalidRequestError.new(
            'You have reached the maximum of 16 test webhook endpoints.', {}
          ))
      end

      it 'delivers an error webhook' do
        payment_provider.update!(secret_key: "sk_test_#{payment_provider.secret_key}")
        result = provider_service.call

        expect(result).to be_success

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            'payment_provider.error',
            payment_provider,
            provider_error: {
              source: 'stripe',
              action: 'payment_provider.register_webhook',
              message: 'You have reached the maximum of 16 test webhook endpoints.',
              code: nil
            }
          )
      end
    end
  end
end
