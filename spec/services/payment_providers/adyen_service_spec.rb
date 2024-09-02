# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::AdyenService, type: :service do
  subject(:adyen_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:api_key) { 'test_api_key_1' }
  let(:code) { 'code_1' }
  let(:name) { 'Name 1' }
  let(:merchant_account) { 'LagoMerchant' }
  let(:success_redirect_url) { Faker::Internet.url }

  describe '.create_or_update' do
    it 'creates an adyen provider' do
      expect do
        adyen_service.create_or_update(organization:, api_key:, code:, name:, merchant_account:, success_redirect_url:)
      end.to change(PaymentProviders::AdyenProvider, :count).by(1)
    end

    context 'when organization already has an adyen provider' do
      let(:adyen_provider) do
        create(:adyen_provider, organization:, api_key: 'api_key_789', code:)
      end

      before { adyen_provider }

      it 'updates the existing provider' do
        result = adyen_service.create_or_update(
          organization:,
          api_key:,
          code:,
          name:,
          success_redirect_url:
        )

        expect(result).to be_success

        aggregate_failures do
          expect(result.adyen_provider.id).to eq(adyen_provider.id)
          expect(result.adyen_provider.api_key).to eq('test_api_key_1')
          expect(result.adyen_provider.code).to eq(code)
          expect(result.adyen_provider.name).to eq(name)
          expect(result.adyen_provider.success_redirect_url).to eq(success_redirect_url)
        end
      end
    end

    context 'with validation error' do
      let(:token) { nil }

      it 'returns an error result' do
        result = adyen_service.create_or_update(
          organization:,
          api_key: nil,
          merchant_account: nil
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

  describe '#handle_incoming_webhook' do
    let(:adyen_provider) { create(:adyen_provider, organization:, hmac_key: nil) }

    let(:body) do
      JSON.parse(event_response_json)['notificationItems'].first&.dig('NotificationRequestItem')
    end

    let(:event_response_json) do
      path = Rails.root.join('spec/fixtures/adyen/webhook_authorisation_response.json')
      File.read(path)
    end

    before { adyen_provider }

    it 'checks the webhook' do
      result = adyen_service.handle_incoming_webhook(
        organization_id: organization.id,
        body:
      )

      expect(result).to be_success

      expect(result.event).to eq(body)
      expect(PaymentProviders::Adyen::HandleEventJob).to have_been_enqueued
    end

    context 'when organization does not exist' do
      subject(:result) do
        adyen_service.handle_incoming_webhook(organization_id: '123456789', body:)
      end

      it 'returns an error' do
        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq('webhook_error')
          expect(result.error.error_message).to eq('Organization not found')
        end
      end
    end

    context 'when payment provider does not exist' do
      subject(:result) do
        adyen_service.handle_incoming_webhook(organization_id: organization.id, body:)
      end

      before do
        adyen_provider.destroy!
      end

      it 'returns an error' do
        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq('payment_provider_not_found')
          expect(result.error.error_message).to eq('Payment provider not found')
        end
      end
    end

    context 'when failing to validate the signature' do
      before do
        adyen_provider.update! hmac_key: '123'
      end

      it 'returns an error' do
        result = adyen_service.handle_incoming_webhook(
          organization_id: organization.id,
          body:
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

  describe '#handle_event' do
    let(:payment_service) { instance_double(Invoices::Payments::AdyenService) }
    let(:payment_provider_service) { instance_double(PaymentProviderCustomers::AdyenService) }
    let(:service_result) { BaseService::Result.new }

    before do
      allow(Invoices::Payments::AdyenService).to receive(:new)
        .and_return(payment_service)
      allow(PaymentProviderCustomers::AdyenService).to receive(:new)
        .and_return(payment_provider_service)
      allow(payment_service).to receive(:update_payment_status)
        .and_return(service_result)
      allow(payment_provider_service).to receive(:preauthorise)
        .and_return(service_result)
    end

    context 'when succeeded authorisation event' do
      let(:event_json) do
        JSON.parse(event_response_json)['notificationItems']
          .first&.dig('NotificationRequestItem').to_json
      end

      let(:event_response_json) do
        path = Rails.root.join('spec/fixtures/adyen/webhook_authorisation_response.json')
        File.read(path)
      end

      it 'routes the event to an other service' do
        adyen_service.handle_event(organization:, event_json:)

        expect(PaymentProviderCustomers::AdyenService).to have_received(:new)
        expect(payment_provider_service).to have_received(:preauthorise)
      end
    end

    context 'when succeeded authorisation event for processed one-time payment' do
      let(:event_json) do
        JSON.parse(event_response_json)['notificationItems']
          .first&.dig('NotificationRequestItem').to_json
      end

      let(:event_response_json) do
        path = Rails.root.join('spec/fixtures/adyen/webhook_authorisation_payment_response.json')
        File.read(path)
      end

      it 'routes the event to an other service' do
        adyen_service.handle_event(organization:, event_json:)

        expect(Invoices::Payments::AdyenService).to have_received(:new)
        expect(payment_service).to have_received(:update_payment_status)
      end
    end

    context "when succeeded authorisation event for processed one-time payment belonging to a Payment Request" do
      let(:payment_service) { instance_double(PaymentRequests::Payments::AdyenService) }

      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_authorisation_payment_response_payment_request.json")
        File.read(path)
      end

      before do
        allow(PaymentRequests::Payments::AdyenService).to receive(:new)
          .and_return(payment_service)
        allow(payment_service).to receive(:update_payment_status)
          .and_return(service_result)
      end

      it "routes the event to an other service" do
        adyen_service.handle_event(organization:, event_json:)

        expect(PaymentRequests::Payments::AdyenService).to have_received(:new)
        expect(payment_service).to have_received(:update_payment_status)
      end
    end

    context "when succeeded authorisation event for processed one-time payment belonging to an invalid payable type" do
      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_authorisation_payment_response_invalid_payable.json")
        File.read(path)
      end

      it "routes the event to an other service" do
        expect {
          adyen_service.handle_event(organization:, event_json:)
        }.to raise_error(NameError, "Invalid lago_payable_type: InvalidPayableTypeName")
      end
    end

    context 'when succeeded refund event' do
      let(:refund_service) { instance_double(CreditNotes::Refunds::AdyenService) }

      let(:event_json) do
        JSON.parse(event_response_json)['notificationItems']
          .first&.dig('NotificationRequestItem').to_json
      end

      let(:event_response_json) do
        path = Rails.root.join('spec/fixtures/adyen/webhook_refund_response.json')
        File.read(path)
      end

      before do
        allow(CreditNotes::Refunds::AdyenService).to receive(:new)
          .and_return(refund_service)
        allow(refund_service).to receive(:update_status)
          .and_return(service_result)
      end

      it 'routes the event to an other service' do
        adyen_service.handle_event(organization:, event_json:)

        expect(CreditNotes::Refunds::AdyenService).to have_received(:new)
        expect(refund_service).to have_received(:update_status)
      end
    end
  end
end
