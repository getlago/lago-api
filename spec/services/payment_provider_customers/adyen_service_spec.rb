# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviderCustomers::AdyenService, type: :service do
  let(:adyen_service) { described_class.new(adyen_customer) }
  let(:customer) { create(:customer, organization:) }
  let(:adyen_provider) { create(:adyen_provider) }
  let(:organization) { adyen_provider.organization }
  let(:adyen_client) { instance_double(Adyen::Client) }
  let(:payment_links_api) { Adyen::PaymentLinksApi.new(adyen_client, 70) }
  let(:checkout) { Adyen::Checkout.new(adyen_client, 70) }
  let(:payment_links_response) { generate(:adyen_payment_links_response) }

  let(:adyen_customer) do
    create(:adyen_customer, customer:, provider_customer_id: nil)
  end

  describe '#create' do
    subject { adyen_service.create }

    before do
      allow(Adyen::Client).to receive(:new).and_return(adyen_client)
      allow(adyen_client).to receive(:checkout).and_return(checkout)
      allow(checkout).to receive(:payment_links_api).and_return(payment_links_api)
      allow(payment_links_api).to receive(:payment_links).and_return(payment_links_response)
    end

    context 'when customer does not have an adyen customer id yet' do
      it 'calls adyen api client payment links' do
        subject
        expect(payment_links_api).to have_received(:payment_links)
      end

      it 'creates a payment link' do
        expect(subject.checkout_url).to eq('https://test.adyen.link/test')
      end

      it 'delivers a success webhook' do
        expect { subject }.to enqueue_job(SendWebhookJob).
          with(
            'customer.checkout_url_generated',
            customer, checkout_url: 
            'https://test.adyen.link/test'
          ).
          on_queue(:webhook)
      end
    end

    context 'when customer already has an adyen customer id' do
      let(:adyen_customer) do
        create(:adyen_customer, customer:, provider_customer_id: 'cus_123456')
      end

      it 'does not call adyen API' do
        expect(payment_links_api).not_to have_received(:payment_links)
      end
    end

    context 'when failing to generate the checkout link' do
      before do
        allow(payment_links_api).
          to receive(:payment_links).and_raise(Adyen::AdyenError.new(nil, nil, 'error'))
      end

      it 'delivers an error webhook' do
        expect { adyen_service.create }
          .to raise_error(Adyen::AdyenError)

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
end
