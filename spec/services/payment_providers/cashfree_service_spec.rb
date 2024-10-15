# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::CashfreeService, type: :service do
  subject(:cashfree_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:code) { 'code_1' }
  let(:name) { 'Name 1' }
  let(:client_id) { '123456_abc' }
  let(:client_secret) { 'cfsk_ma_prod_abc_123456' }
  let(:success_redirect_url) { Faker::Internet.url }

  describe '.create_or_update' do
    it 'creates a cashfree provider' do
      expect do
        cashfree_service.create_or_update(
          organization:,
          code:,
          name:,
          client_id:,
          client_secret:,
          success_redirect_url:
        )
      end.to change(PaymentProviders::CashfreeProvider, :count).by(1)
    end

    context 'when organization already have a cashfree provider' do
      let(:cashfree_provider) do
        create(:cashfree_provider, organization:, client_id: '123456_abc_old', client_secret: 'cfsk_ma_prod_abc_123456_old', code:)
      end

      before { cashfree_provider }

      it 'updates the existing provider' do
        result = cashfree_service.create_or_update(
          organization:,
          code:,
          name:,
          client_id:,
          client_secret:,
          success_redirect_url:
        )

        expect(result).to be_success

        aggregate_failures do
          expect(result.cashfree_provider.id).to eq(cashfree_provider.id)
          expect(result.cashfree_provider.client_id).to eq('123456_abc')
          expect(result.cashfree_provider.client_secret).to eq('cfsk_ma_prod_abc_123456')
          expect(result.cashfree_provider.code).to eq(code)
          expect(result.cashfree_provider.name).to eq(name)
          expect(result.cashfree_provider.success_redirect_url).to eq(success_redirect_url)
        end
      end
    end

    context 'with validation error' do
      let(:token) { nil }

      it 'returns an error result' do
        result = cashfree_service.create_or_update(
          organization:
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:client_id]).to eq(['value_is_mandatory'])
          expect(result.error.messages[:client_secret]).to eq(['value_is_mandatory'])
        end
      end
    end
  end

  describe '.handle_incoming_webhook' do
    let(:cashfree_provider) { create(:cashfree_provider, organization:, client_id:, client_secret:) }

    let(:body) do
      path = Rails.root.join('spec/fixtures/cashfree/event.json')
      File.read(path)
    end

    before { cashfree_provider }

    it 'checks the webhook' do
      result = cashfree_service.handle_incoming_webhook(
        organization_id: organization.id,
        body:,
        timestamp: '1629271506',
        signature: 'MFB3Rkubs4jB97ROS/I4iu9llAAP5ykJ3GZYp95o/Mw='
      )

      expect(result).to be_success

      expect(PaymentProviders::Cashfree::HandleEventJob).to have_been_enqueued
    end

    context 'when failing to validate the signature' do
      it 'returns an error' do
        result = cashfree_service.handle_incoming_webhook(
          organization_id: organization.id,
          body:,
          timestamp: '1629271506',
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
    let(:payment_service) { instance_double(Invoices::Payments::CashfreeService) }
    let(:service_result) { BaseService::Result.new }

    before do
      allow(Invoices::Payments::CashfreeService).to receive(:new)
        .and_return(payment_service)
      allow(payment_service).to receive(:update_payment_status)
        .and_return(service_result)
    end

    context 'when succeeded payment event' do
      let(:event) do
        path = Rails.root.join('spec/fixtures/cashfree/event.json')
        File.read(path)
      end

      it 'routes the event to an other service' do
        cashfree_service.handle_event(event_json: event)

        expect(Invoices::Payments::CashfreeService).to have_received(:new)
        expect(payment_service).to have_received(:update_payment_status)
      end
    end
  end
end
