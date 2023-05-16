# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::AdyenService, type: :service do
  subject(:adyen_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe '.create_or_update' do
    it 'creates a adyen provider' do
      expect do
        adyen_service.create_or_update(
          organization:,
          access_code:,
        )
      end.to change(PaymentProviders::AdyenProvider, :count).by(1)
    end

    context 'when organization already have a adyen provider' do
      let(:adyen_provider) do
        create(:adyen_provider, organization:, access_token: 'access_token_123')
      end

      before { adyen_provider }

      it 'updates the existing provider' do
        result = adyen_service.create_or_update(
          organization:,
          access_code:,
        )

        expect(result).to be_success

        aggregate_failures do
          expect(result.adyen_provider.id).to eq(adyen_provider.id)
          expect(result.adyen_provider.access_token).to eq('access_token_554')
        end
      end
    end

    context 'with validation error' do
      let(:token) { nil }

      it 'returns an error result' do
        result = adyen_service.create_or_update(
          organization:,
          access_code:,
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:api_key]).to eq(['value_is_mandatory'])
          expect(result.error.messages[:merchant_account]).to eq(['value_is_mandatory'])
        end
      end
    end
  end

  describe '.handle_incoming_webhook' do
    let(:adyen_provider) { create(:adyen_provider, organization:) }
    let(:events_result) { events['events'].map { |event| GoCardlessPro::Resources::Event.new(event) } }

    let(:events) do
      path = Rails.root.join('spec/fixtures/adyen/events.json')
      JSON.parse(File.read(path))
    end

    before { adyen_provider }

    it 'checks the webhook' do
      allow(GoCardlessPro::Webhook).to receive(:parse)
        .and_return(events_result)

      result = adyen_service.handle_incoming_webhook(
        organization_id: organization.id,
        body: events.to_json
      )

      expect(result).to be_success

      expect(result.events).to eq(events_result)
      expect(PaymentProviders::Adyen::HandleEventJob).to have_been_enqueued
    end

    context 'when failing to parse payload' do
      it 'returns an error' do
        allow(GoCardlessPro::Webhook).to receive(:parse).and_raise(JSON::ParserError)

        result = adyen_service.handle_incoming_webhook(
          organization_id: organization.id,
          body: events.to_json,
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
        allow(GoCardlessPro::Webhook).to receive(:parse)
          .and_raise(GoCardlessPro::Webhook::InvalidSignatureError.new('error'))

        result = adyen_service.handle_incoming_webhook(
          organization_id: organization.id,
          body: events.to_json,
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
    let(:payment_service) { instance_double(Invoices::Payments::AdyenService) }
    let(:service_result) { BaseService::Result.new }

    before do
      allow(Invoices::Payments::AdyenService).to receive(:new)
        .and_return(payment_service)
      allow(payment_service).to receive(:update_payment_status)
        .and_return(service_result)
    end

    context 'when succeeded payment event' do
      let(:events) do
        path = Rails.root.join('spec/fixtures/adyen/events.json')
        File.read(path)
      end

      it 'routes the event to an other service' do
        adyen_service.handle_event(events_json: events)

        expect(Invoices::Payments::AdyenService).to have_received(:new)
        expect(payment_service).to have_received(:update_payment_status)
      end
    end

    context 'when succeeded refund event' do
      let(:refund_service) { instance_double(CreditNotes::Refunds::AdyenService) }
      let(:events) do
        path = Rails.root.join('spec/fixtures/adyen/events_refund.json')
        File.read(path)
      end

      before do
        allow(CreditNotes::Refunds::AdyenService).to receive(:new)
          .and_return(refund_service)
        allow(refund_service).to receive(:update_status)
          .and_return(service_result)
      end

      it 'routes the event to an other service' do
        adyen_service.handle_event(events_json: events)

        expect(CreditNotes::Refunds::AdyenService).to have_received(:new)
        expect(refund_service).to have_received(:update_status)
      end
    end
  end
end
