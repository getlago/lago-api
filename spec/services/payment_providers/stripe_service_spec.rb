# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::StripeService, type: :service do
  subject(:stripe_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:code) { 'code_1' }
  let(:name) { 'Name 1' }
  let(:public_key) { SecureRandom.uuid }
  let(:secret_key) { SecureRandom.uuid }
  let(:success_redirect_url) { Faker::Internet.url }

  describe '.create_or_update' do
    it 'creates a stripe provider' do
      expect do
        result = stripe_service.create_or_update(
          organization_id: organization.id,
          secret_key:,
          code:,
          name:,
          success_redirect_url:
        )

        expect(PaymentProviders::Stripe::RegisterWebhookJob).to have_been_enqueued
          .with(result.stripe_provider)
      end.to change(PaymentProviders::StripeProvider, :count).by(1)
    end

    context 'when code was changed' do
      let(:new_code) { 'updated_code_2' }
      let(:stripe_customer) { create(:stripe_customer, payment_provider:, customer:) }
      let(:customer) { create(:customer, organization:) }

      let(:payment_provider) do
        create(
          :stripe_provider,
          organization:,
          code:,
          name:,
          secret_key: 'secret'
        )
      end

      before { stripe_customer }

      it 'updates payment provider codes of all customers' do
        result = stripe_service.create_or_update(
          id: payment_provider.id,
          organization_id: organization.id,
          code: new_code,
          name:,
          secret_key: 'secret'
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.stripe_provider.customers.first.payment_provider_code).to eq(new_code)
        end
      end
    end

    context 'when organization already have a stripe provider' do
      let(:stripe_provider) do
        create(
          :stripe_provider,
          organization:,
          code:,
          name:,
          webhook_id: 'we_123456',
          secret_key: 'secret'
        )
      end

      before do
        stripe_provider

        allow(::Stripe::WebhookEndpoint).to receive(:delete)
          .with('we_123456', {}, {api_key: 'secret'})
      end

      it 'updates the existing provider' do
        result = stripe_service.create_or_update(
          organization_id: organization.id,
          secret_key:,
          code:,
          name:,
          success_redirect_url:
        )

        expect(result).to be_success

        aggregate_failures do
          expect(result.stripe_provider.id).to eq(stripe_provider.id)
          expect(result.stripe_provider.secret_key).to eq(secret_key)
          expect(result.stripe_provider.code).to eq(code)
          expect(result.stripe_provider.name).to eq(name)
          expect(result.stripe_provider.success_redirect_url).to eq(success_redirect_url)

          expect(PaymentProviders::Stripe::RegisterWebhookJob).to have_been_enqueued
            .with(stripe_provider)
          expect(::Stripe::WebhookEndpoint).to have_received(:delete)
        end
      end
    end

    context 'with validation error' do
      it 'returns an error result' do
        result = stripe_service.create_or_update(
          organization_id: organization.id,
          secret_key: nil
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:secret_key]).to eq(['value_is_mandatory'])
        end
      end
    end
  end

  describe '.refresh_webhook' do
    let(:stripe_provider) do
      create(:stripe_provider, organization:)
    end

    let(:stripe_webhook) do
      ::Stripe::WebhookEndpoint.construct_from(
        id: 'we_123456',
        secret: 'whsec_123456'
      )
    end

    before do
      allow(::Stripe::WebhookEndpoint).to receive(:delete)
        .with('we_123456', {}, {api_key: 'secret'})

      allow(::Stripe::WebhookEndpoint)
        .to receive(:create)
        .and_return(stripe_webhook)
    end

    it 'registers a webhook on stripe' do
      result = stripe_service.refresh_webhook(stripe_provider:)

      expect(result).to be_success

      aggregate_failures do
        expect(result.payment_provider.webhook_id).to eq('we_123456')
        expect(result.payment_provider.webhook_secret).to eq('whsec_123456')
      end
    end
  end

  describe '.handle_incoming_webhook' do
    let(:stripe_provider) { create(:stripe_provider, organization:) }
    let(:event_result) { Stripe::Event.construct_from(event) }

    let(:event) do
      path = Rails.root.join('spec/fixtures/stripe/payment_intent_event.json')
      JSON.parse(File.read(path))
    end

    before { stripe_provider }

    it 'checks the webhook' do
      allow(::Stripe::Webhook).to receive(:construct_event)
        .and_return(event_result)

      result = stripe_service.handle_incoming_webhook(
        organization_id: organization.id,
        params: event.to_json,
        signature: 'signature'
      )

      expect(result).to be_success

      expect(result.event).to eq(event_result)
      expect(PaymentProviders::Stripe::HandleEventJob).to have_been_enqueued
    end

    context 'when failing to parse payload' do
      it 'returns an error' do
        allow(::Stripe::Webhook).to receive(:construct_event)
          .and_raise(JSON::ParserError)

        result = stripe_service.handle_incoming_webhook(
          organization_id: organization.id,
          params: event.to_json,
          signature: 'signature'
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq('webhook_error')
          expect(result.error.error_message).to eq('Invalid payload')
        end
      end
    end

    context 'when failing to validate the signature' do
      it 'returns an error' do
        allow(::Stripe::Webhook).to receive(:construct_event)
          .and_raise(::Stripe::SignatureVerificationError.new(
            'error', 'signature', http_body: event.to_json
          ))

        result = stripe_service.handle_incoming_webhook(
          organization_id: organization.id,
          params: event.to_json,
          signature: 'signature'
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq('webhook_error')
          expect(result.error.error_message).to eq('Invalid signature')
        end
      end
    end
  end
end
