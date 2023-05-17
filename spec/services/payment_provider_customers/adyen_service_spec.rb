# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviderCustomers::AdyenService, type: :service do
  subject(:adyen_service) { described_class.new(adyen_customer) }

  let(:customer) { create(:customer, organization:) }
  let(:adyen_provider) { create(:adyen_provider) }
  let(:organization) { adyen_provider.organization }
  let(:adyen_client) { instance_double(GoCardlessPro::Client) }
  let(:adyen_customers_service) { instance_double(GoCardlessPro::Services::CustomersService) }
  let(:adyen_billing_request_service) { instance_double(GoCardlessPro::Services::BillingRequestsService) }
  let(:adyen_billing_request_flow_service) { instance_double(GoCardlessPro::Services::BillingRequestFlowsService) }

  let(:adyen_customer) do
    create(:adyen_customer, customer:, provider_customer_id: nil)
  end

  describe '#create' do
    before do
      allow(GoCardlessPro::Client).to receive(:new)
        .and_return(adyen_client)
      allow(adyen_client).to receive(:customers)
        .and_return(adyen_customers_service)
      allow(adyen_customers_service).to receive(:create)
        .and_return(GoCardlessPro::Resources::Customer.new('id' => '123'))
    end

    it 'creates the adyen customer' do
      result = adyen_service.create

      expect(adyen_customers_service).to have_received(:create)
      expect(result.adyen_customer.provider_customer_id).to eq('123')
    end

    it 'delivers a success webhook' do
      adyen_service.create

      expect(adyen_customers_service).to have_received(:create)
      expect(SendWebhookJob).to have_been_enqueued
        .with('customer.payment_provider_created', customer)
    end

    it 'triggers checkout job' do
      adyen_service.create

      expect(adyen_customers_service).to have_received(:create)
      expect(PaymentProviderCustomers::AdyenCheckoutUrlJob).to have_been_enqueued
        .with(adyen_customer)
    end

    context 'when customer already have a adyen customer id' do
      let(:adyen_customer) do
        create(:adyen_customer, customer:, provider_customer_id: 'cus_123456')
      end

      it 'does not call adyen API' do
        adyen_service.create

        expect(adyen_customers_service).not_to have_received(:create)
      end
    end

    context 'when failing to create the customer' do
      it 'delivers an error webhook' do
        allow(GoCardlessPro::Client).to receive(:new)
          .and_raise(GoCardlessPro::ApiError.new({ 'message' => 'error' }))

        expect { adyen_service.create }
          .to raise_error(GoCardlessPro::ApiError)

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            'customer.payment_provider_error',
            customer,
            provider_error: {
              message: 'error',
              error_code: nil,
            },
          )
      end
    end
  end

  describe '#generate_checkout_url' do
    before do
      allow(GoCardlessPro::Client).to receive(:new)
        .and_return(adyen_client)
      allow(adyen_client).to receive(:billing_requests)
        .and_return(adyen_billing_request_service)
      allow(adyen_billing_request_service).to receive(:create)
        .and_return(GoCardlessPro::Resources::BillingRequest.new('id' => '123'))

      allow(adyen_client).to receive(:billing_request_flows)
        .and_return(adyen_billing_request_flow_service)
      allow(adyen_billing_request_flow_service).to receive(:create)
        .and_return(GoCardlessPro::Resources::BillingRequestFlow.new('authorisation_url' => 'https://example.com'))
    end

    it 'receives billing request flow response' do
      adyen_service.generate_checkout_url

      aggregate_failures do
        expect(adyen_billing_request_service).to have_received(:create)
        expect(adyen_billing_request_flow_service).to have_received(:create)
      end
    end

    it 'delivers a webhook with checkout url' do
      adyen_service.generate_checkout_url

      aggregate_failures do
        expect(adyen_billing_request_service).to have_received(:create)
        expect(adyen_billing_request_flow_service).to have_received(:create)
        expect(SendWebhookJob).to have_been_enqueued
          .with('customer.checkout_url_generated', customer, checkout_url: 'https://example.com')
      end
    end
  end
end
