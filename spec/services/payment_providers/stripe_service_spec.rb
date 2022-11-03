# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::StripeService, type: :service do
  subject(:stripe_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:public_key) { SecureRandom.uuid }
  let(:secret_key) { SecureRandom.uuid }

  describe '.create_or_update' do
    it 'creates a stripe provider' do
      expect do
        result = stripe_service.create_or_update(
          organization_id: organization.id,
          secret_key: secret_key,
          create_customers: true,
        )

        expect(PaymentProviders::Stripe::RegisterWebhookJob).to have_been_enqueued
          .with(result.stripe_provider)
      end.to change(PaymentProviders::StripeProvider, :count).by(1)
    end

    context 'when organization already have a stripe provider' do
      let(:stripe_provider) do
        create(
          :stripe_provider,
          organization: organization,
          webhook_id: 'we_123456',
          secret_key: 'secret',
        )
      end

      before do
        stripe_provider

        allow(::Stripe::WebhookEndpoint).to receive(:delete)
          .with('we_123456', {}, { api_key: 'secret' })
      end

      it 'updates the existing provider' do
        result = stripe_service.create_or_update(
          organization_id: organization.id,
          secret_key: secret_key,
          create_customers: true,
        )

        expect(result).to be_success

        aggregate_failures do
          expect(result.stripe_provider.id).to eq(stripe_provider.id)
          expect(result.stripe_provider.secret_key).to eq(secret_key)
          expect(result.stripe_provider.create_customers).to be_truthy

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
          secret_key: nil,
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:secret_key]).to eq(['value_is_mandatory'])
          expect(result.error.messages[:create_customers]).to eq(['value_is_invalid'])
        end
      end
    end
  end

  describe '.register_webhook' do
    let(:stripe_provider) do
      create(:stripe_provider, organization: organization)
    end

    let(:stripe_webhook) do
      ::Stripe::WebhookEndpoint.construct_from(
        id: 'we_123456',
        secret: 'whsec_123456',
      )
    end

    before do
      allow(::Stripe::WebhookEndpoint)
        .to receive(:create)
        .and_return(stripe_webhook)
    end

    it 'registers a webhook on stripe' do
      result = stripe_service.register_webhook(stripe_provider)

      expect(result).to be_success

      aggregate_failures do
        expect(result.stripe_provider.webhook_id).to eq('we_123456')
        expect(result.stripe_provider.webhook_secret).to eq('whsec_123456')
      end
    end
  end

  describe '.refresh_webhook' do
    let(:stripe_provider) do
      create(:stripe_provider, organization: organization)
    end

    let(:stripe_webhook) do
      ::Stripe::WebhookEndpoint.construct_from(
        id: 'we_123456',
        secret: 'whsec_123456',
      )
    end

    before do
      allow(::Stripe::WebhookEndpoint).to receive(:delete)
        .with('we_123456', {}, { api_key: 'secret' })

      allow(::Stripe::WebhookEndpoint)
        .to receive(:create)
        .and_return(stripe_webhook)
    end

    it 'registers a webhook on stripe' do
      result = stripe_service.refresh_webhook(stripe_provider: stripe_provider)

      expect(result).to be_success

      aggregate_failures do
        expect(result.stripe_provider.webhook_id).to eq('we_123456')
        expect(result.stripe_provider.webhook_secret).to eq('whsec_123456')
      end
    end
  end

  describe '.handle_incoming_webhook' do
    let(:stripe_provider) { create(:stripe_provider, organization: organization) }
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
        signature: 'signature',
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
          signature: 'signature',
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
          signature: 'signature',
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

  describe '.handle_event' do
    let(:payment_service) { instance_double(Invoices::Payments::StripeService) }
    let(:provider_customer_service) { instance_double(PaymentProviderCustomers::StripeService) }
    let(:service_result) { BaseService::Result.new }

    before do
      allow(Invoices::Payments::StripeService).to receive(:new)
        .and_return(payment_service)
      allow(payment_service).to receive(:update_status)
        .and_return(service_result)
    end

    context 'when payment intent event' do
      let(:event) do
        path = Rails.root.join('spec/fixtures/stripe/payment_intent_event.json')
        File.read(path)
      end

      it 'routes the event to an other service' do
        result = stripe_service.handle_event(
          organization: organization,
          event_json: event,
        )

        expect(result).to be_success

        expect(Invoices::Payments::StripeService).to have_received(:new)
        expect(payment_service).to have_received(:update_status)
      end
    end

    context 'when setup intent event' do
      let(:event) do
        path = Rails.root.join('spec/fixtures/stripe/setup_intent_event.json')
        File.read(path)
      end

      before do
        allow(PaymentProviderCustomers::StripeService).to receive(:new)
          .and_return(provider_customer_service)
        allow(provider_customer_service).to receive(:update_payment_method)
          .and_return(service_result)
      end

      it 'routes the event to an other service' do
        result = stripe_service.handle_event(
          organization: organization,
          event_json: event,
        )

        expect(result).to be_success

        expect(PaymentProviderCustomers::StripeService).to have_received(:new)
        expect(provider_customer_service).to have_received(:update_payment_method)
      end
    end

    context 'when payment method detached event' do
      let(:event) do
        path = Rails.root.join('spec/fixtures/stripe/payment_method_detached_event.json')
        File.read(path)
      end

      before do
        allow(PaymentProviderCustomers::StripeService).to receive(:new)
          .and_return(provider_customer_service)
        allow(provider_customer_service).to receive(:delete_payment_method)
          .and_return(service_result)
      end

      it 'routes the event to an other service' do
        result = stripe_service.handle_event(
          organization: organization,
          event_json: event,
        )

        expect(result).to be_success

        expect(PaymentProviderCustomers::StripeService).to have_received(:new)
        expect(provider_customer_service).to have_received(:delete_payment_method)
      end
    end

    context 'when refund updated event' do
      let(:refund_service) { instance_double(CreditNotes::Refunds::StripeService) }

      let(:event) do
        path = Rails.root.join('spec/fixtures/stripe/charge_refund_updated_event.json')
        File.read(path)
      end

      before do
        allow(CreditNotes::Refunds::StripeService).to receive(:new)
          .and_return(refund_service)
        allow(refund_service).to receive(:update_status)
          .and_return(service_result)
      end

      it 'routes the event to an other service' do
        result = stripe_service.handle_event(
          organization: organization,
          event_json: event,
        )

        expect(result).to be_success

        expect(CreditNotes::Refunds::StripeService).to have_received(:new)
        expect(refund_service).to have_received(:update_status)
      end
    end

    context 'when event does not match an expected event type' do
      let(:event) do
        {
          id: 'foo',
          type: 'invalid',
          data: {
            object: { id: 'foo' },
          },
        }
      end

      it 'returns an error result' do
        result = stripe_service.handle_event(
          organization: organization,
          event_json: event.to_json,
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq('webhook_error')
          expect(result.error.error_message).to eq('Invalid stripe event type: invalid')
        end

        expect(Invoices::Payments::StripeService).not_to have_received(:new)
        expect(payment_service).not_to have_received(:update_status)
      end
    end
  end
end
