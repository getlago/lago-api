# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::Stripe::HandleEventService do
  subject(:event_service) { described_class.new(organization:, event_json:) }

  let(:organization) { create(:organization) }

  let(:payment_service) { instance_double(Invoices::Payments::StripeService) }
  let(:provider_customer_service) { instance_double(PaymentProviderCustomers::StripeService) }
  let(:service_result) { BaseService::Result.new }

  before do
    allow(Invoices::Payments::StripeService).to receive(:new)
      .and_return(payment_service)
    allow(payment_service).to receive(:update_payment_status)
      .and_return(service_result)
  end

  context 'when payment intent event' do
    let(:event_json) do
      path = Rails.root.join('spec/fixtures/stripe/payment_intent_event.json')
      File.read(path)
    end

    it 'routes the event to an other service' do
      result = event_service.call

      expect(result).to be_success

      expect(Invoices::Payments::StripeService).to have_received(:new)
      expect(payment_service).to have_received(:update_payment_status)
        .with(
          organization_id: organization.id,
          provider_payment_id: 'pi_1JKS2Y2VYugoKSBzNHPFBNj9',
          status: 'succeeded',
          metadata: {
            lago_invoice_id: 'a587e552-36bc-4334-81f2-abcbf034ad3f'
          }
        )
    end
  end

  context "when payment intent event for a payment request" do
    let(:payment_service) { instance_double(PaymentRequests::Payments::StripeService) }

    let(:event_json) do
      path = Rails.root.join("spec/fixtures/stripe/payment_intent_event_payment_request.json")
      File.read(path)
    end

    before do
      allow(PaymentRequests::Payments::StripeService).to receive(:new)
        .and_return(payment_service)
      allow(payment_service).to receive(:update_payment_status)
        .and_return(service_result)
    end

    it "routes the event to an other service" do
      result = event_service.call

      expect(result).to be_success

      expect(PaymentRequests::Payments::StripeService).to have_received(:new)
      expect(payment_service).to have_received(:update_payment_status)
        .with(
          organization_id: organization.id,
          provider_payment_id: "pi_1JKS2Y2VYugoKSBzNHPFBNj9",
          status: "succeeded",
          metadata: {
            lago_payment_request_id: "a587e552-36bc-4334-81f2-abcbf034ad3f",
            lago_payable_type: "PaymentRequest"
          }
        )
    end
  end

  context "when payment intent event with an invalid payable type" do
    let(:event_json) do
      path = Rails.root.join("spec/fixtures/stripe/payment_intent_event_invalid_payable_type.json")
      File.read(path)
    end

    it "routes the event to an other service" do
      expect { event_service.call }.to raise_error(NameError, "Invalid lago_payable_type: InvalidPayableTypeName")
    end
  end

  context 'when charge event' do
    let(:event_json) do
      path = Rails.root.join('spec/fixtures/stripe/charge_event.json')
      File.read(path)
    end

    it 'routes the event to an other service' do
      result = event_service.call

      expect(result).to be_success

      expect(Invoices::Payments::StripeService).to have_received(:new)
      expect(payment_service).to have_received(:update_payment_status)
        .with(
          organization_id: organization.id,
          provider_payment_id: 'pi_123456',
          status: 'succeeded',
          metadata: {}
        )
    end
  end

  context "when charge event for a payment request" do
    let(:payment_service) { instance_double(PaymentRequests::Payments::StripeService) }

    let(:event_json) do
      path = Rails.root.join("spec/fixtures/stripe/charge_event_payment_request.json")
      File.read(path)
    end

    before do
      allow(PaymentRequests::Payments::StripeService).to receive(:new)
        .and_return(payment_service)
      allow(payment_service).to receive(:update_payment_status)
        .and_return(service_result)
    end

    it "routes the event to an other service" do
      result = event_service.call

      expect(result).to be_success

      expect(PaymentRequests::Payments::StripeService).to have_received(:new)
      expect(payment_service).to have_received(:update_payment_status)
        .with(
          organization_id: organization.id,
          provider_payment_id: 'pi_123456',
          status: "succeeded",
          metadata: {
            lago_payment_request_id: "a587e552-36bc-4334-81f2-abcbf034ad3f",
            lago_payable_type: "PaymentRequest"
          }
        )
    end
  end

  context "when charge event with an invalid payable type" do
    let(:event_json) do
      path = Rails.root.join("spec/fixtures/stripe/charge_event_invalid_payable_type.json")
      File.read(path)
    end

    it "routes the event to an other service" do
      expect { event_service.call }.to raise_error(NameError, "Invalid lago_payable_type: InvalidPayableTypeName")
    end
  end

  context 'when setup intent event' do
    let(:event_json) do
      path = Rails.root.join('spec/fixtures/stripe/setup_intent_event.json')
      File.read(path)
    end

    before do
      allow(PaymentProviders::Stripe::Webhooks::SetupIntentSucceededService).to receive(:call)
        .and_return(service_result)
    end

    it 'routes the event to an other service' do
      result = event_service.call

      expect(result).to be_success

      expect(PaymentProviders::Stripe::Webhooks::SetupIntentSucceededService).to have_received(:call)
    end
  end

  context 'when customer updated event' do
    let(:event_json) do
      path = Rails.root.join('spec/fixtures/stripe/customer_updated_event.json')
      File.read(path)
    end

    before do
      allow(PaymentProviders::Stripe::Webhooks::CustomerUpdatedService).to receive(:call)
        .and_return(service_result)
    end

    it 'routes the event to an other service' do
      result = event_service.call

      expect(result).to be_success

      expect(PaymentProviders::Stripe::Webhooks::CustomerUpdatedService).to have_received(:call)
    end
  end

  context 'when payment method detached event' do
    let(:event_json) do
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
      result = event_service.call

      expect(result).to be_success

      expect(PaymentProviderCustomers::StripeService).to have_received(:new)
      expect(provider_customer_service).to have_received(:delete_payment_method)
    end
  end

  context 'when refund updated event' do
    let(:refund_service) { instance_double(CreditNotes::Refunds::StripeService) }

    let(:event_json) do
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
      result = event_service.call

      expect(result).to be_success

      expect(CreditNotes::Refunds::StripeService).to have_received(:new)
      expect(refund_service).to have_received(:update_status)
    end
  end

  context 'when event does not match an expected event type' do
    let(:event_json) do
      {
        id: 'foo',
        type: 'invalid',
        data: {
          object: {id: 'foo'}
        }
      }.to_json
    end

    it 'returns an empty result' do
      result = event_service.call

      aggregate_failures do
        expect(result).to be_success

        expect(Invoices::Payments::StripeService).not_to have_received(:new)
        expect(payment_service).not_to have_received(:update_payment_status)
      end
    end
  end
end
