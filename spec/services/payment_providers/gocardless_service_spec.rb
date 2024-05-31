# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::GocardlessService, type: :service do
  subject(:gocardless_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:access_code) { '1234567!abc' }
  let(:code) { 'code_1' }
  let(:name) { 'Name 1' }
  let(:oauth_client) { instance_double(OAuth2::Client) }
  let(:auth_code_strategy) { instance_double(OAuth2::Strategy::AuthCode) }
  let(:access_token) { instance_double(OAuth2::AccessToken) }
  let(:token) { 'access_token_554' }
  let(:success_redirect_url) { Faker::Internet.url }

  before do
    allow(OAuth2::Client).to receive(:new)
      .and_return(oauth_client)
    allow(oauth_client).to receive(:auth_code)
      .and_return(auth_code_strategy)
    allow(auth_code_strategy).to receive(:get_token)
      .and_return(access_token)
    allow(access_token).to receive(:token)
      .and_return(token)
  end

  describe '.create_or_update' do
    it 'creates a gocardless provider' do
      expect do
        gocardless_service.create_or_update(
          organization:,
          access_code:,
          code:,
          name:,
          success_redirect_url:
        )
      end.to change(PaymentProviders::GocardlessProvider, :count).by(1)
    end

    context 'when organization already have a gocardless provider' do
      let(:gocardless_provider) do
        create(:gocardless_provider, organization:, access_token: 'access_token_123', code:)
      end

      before { gocardless_provider }

      it 'updates the existing provider' do
        result = gocardless_service.create_or_update(
          organization:,
          access_code:,
          code:,
          name:,
          success_redirect_url:
        )

        expect(result).to be_success

        aggregate_failures do
          expect(result.gocardless_provider.id).to eq(gocardless_provider.id)
          expect(result.gocardless_provider.access_token).to eq('access_token_554')
          expect(result.gocardless_provider.code).to eq(code)
          expect(result.gocardless_provider.name).to eq(name)
          expect(result.gocardless_provider.success_redirect_url).to eq(success_redirect_url)
        end
      end
    end

    context 'with validation error' do
      let(:token) { nil }

      it 'returns an error result' do
        result = gocardless_service.create_or_update(
          organization:,
          access_code:
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:access_token]).to eq(['value_is_mandatory'])
        end
      end
    end
  end

  describe '.handle_incoming_webhook' do
    let(:gocardless_provider) { create(:gocardless_provider, organization:) }
    let(:events_result) { events['events'].map { |event| GoCardlessPro::Resources::Event.new(event) } }

    let(:events) do
      path = Rails.root.join('spec/fixtures/gocardless/events.json')
      JSON.parse(File.read(path))
    end

    before { gocardless_provider }

    it 'checks the webhook' do
      allow(GoCardlessPro::Webhook).to receive(:parse)
        .and_return(events_result)

      result = gocardless_service.handle_incoming_webhook(
        organization_id: organization.id,
        body: events.to_json,
        signature: 'signature'
      )

      expect(result).to be_success

      expect(result.events).to eq(events_result)
      expect(PaymentProviders::Gocardless::HandleEventJob).to have_been_enqueued
    end

    context 'when failing to parse payload' do
      it 'returns an error' do
        allow(GoCardlessPro::Webhook).to receive(:parse).and_raise(JSON::ParserError)

        result = gocardless_service.handle_incoming_webhook(
          organization_id: organization.id,
          body: events.to_json,
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
        allow(GoCardlessPro::Webhook).to receive(:parse)
          .and_raise(GoCardlessPro::Webhook::InvalidSignatureError.new('error'))

        result = gocardless_service.handle_incoming_webhook(
          organization_id: organization.id,
          body: events.to_json,
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

  describe '.handle_event' do
    let(:payment_service) { instance_double(Invoices::Payments::GocardlessService) }
    let(:service_result) { BaseService::Result.new }

    before do
      allow(Invoices::Payments::GocardlessService).to receive(:new)
        .and_return(payment_service)
      allow(payment_service).to receive(:update_payment_status)
        .and_return(service_result)
    end

    context 'when succeeded payment event' do
      let(:events) do
        path = Rails.root.join('spec/fixtures/gocardless/events.json')
        File.read(path)
      end

      it 'routes the event to an other service' do
        gocardless_service.handle_event(events_json: events)

        expect(Invoices::Payments::GocardlessService).to have_received(:new)
        expect(payment_service).to have_received(:update_payment_status)
      end
    end

    context 'when succeeded refund event' do
      let(:refund_service) { instance_double(CreditNotes::Refunds::GocardlessService) }
      let(:events) do
        path = Rails.root.join('spec/fixtures/gocardless/events_refund.json')
        File.read(path)
      end

      before do
        allow(CreditNotes::Refunds::GocardlessService).to receive(:new)
          .and_return(refund_service)
        allow(refund_service).to receive(:update_status)
          .and_return(service_result)
      end

      it 'routes the event to an other service' do
        gocardless_service.handle_event(events_json: events)

        expect(CreditNotes::Refunds::GocardlessService).to have_received(:new)
        expect(refund_service).to have_received(:update_status)
      end
    end
  end
end
