# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::Payments::CreateService, type: :service do
  subject(:create_service) { described_class.new(invoice:, payment_provider: provider) }

  let(:organization) { create(:organization) }
  let(:invoice) { create(:invoice, customer:, organization:, total_amount_cents: 100) }
  let(:customer) { create(:customer, organization:, payment_provider: provider, payment_provider_code:) }
  let(:provider) { 'stripe' }
  let(:payment_provider_code) { 'stripe_1' }
  let(:payment_provider) { create(:stripe_provider, code: payment_provider_code, organization:) }

  describe '#call' do
    let(:result) { BaseService::Result.new }
    let(:provider_class) { Invoices::Payments::StripeService }
    let(:provider_service) { instance_double(provider_class) }

    before do
      payment_provider

      allow(provider_class)
        .to receive(:new).with(invoice)
        .and_return(provider_service)
      allow(provider_service).to receive(:call)
        .and_return(result)
    end

    it 'calls the stripe service' do
      create_service.call

      expect(provider_class).to have_received(:new).with(invoice)
      expect(provider_service).to have_received(:call)
    end

    context 'with gocardless payment provider' do
      let(:provider) { 'gocardless' }
      let(:provider_class) { Invoices::Payments::GocardlessService }
      let(:payment_provider) { create(:gocardless_provider, code: payment_provider_code, organization:) }

      it 'calls the gocardless service' do
        create_service.call

        expect(provider_class).to have_received(:new).with(invoice)
        expect(provider_service).to have_received(:call)
      end
    end

    context 'with adyen payment provider' do
      let(:provider) { 'adyen' }
      let(:provider_class) { Invoices::Payments::AdyenService }
      let(:payment_provider) { create(:adyen_provider, code: payment_provider_code, organization:) }

      it 'calls the adyen service' do
        create_service.call

        expect(provider_class).to have_received(:new).with(invoice)
        expect(provider_service).to have_received(:call)
      end
    end

    context 'when invoice is payment_succeeded' do
      before { invoice.payment_succeeded! }

      it 'does not creates a payment' do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
        expect(provider_class).not_to have_received(:new)
      end
    end

    context 'when invoice is voided' do
      before { invoice.voided! }

      it 'does not creates a payment' do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
        expect(provider_class).not_to have_received(:new)
      end
    end

    context 'when invoice amount is 0' do
      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          total_amount_cents: 0,
          currency: 'EUR'
        )
      end

      it 'does not creates a payment' do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
        expect(result.invoice).to be_payment_succeeded
        expect(provider_class).not_to have_received(:new)
      end
    end

    context 'with missing payment provider' do
      let(:payment_provider) { nil }

      it 'does not creates a payment' do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
        expect(provider_class).not_to have_received(:new)
      end
    end
  end

  describe '#call_async' do
    it 'enqueues a job to create a stripe payment' do
      expect { create_service.call_async }
        .to have_enqueued_job(Invoices::Payments::CreateJob)
        .with(invoice:, payment_provider: :stripe)
    end

    context 'with gocardless payment provider' do
      let(:provider) { 'gocardless' }

      it 'enqueues a job to create a gocardless payment' do
        expect { create_service.call_async }
          .to have_enqueued_job(Invoices::Payments::CreateJob)
          .with(invoice:, payment_provider: :gocardless)
      end
    end

    context 'with adyen payment provider' do
      let(:provider) { 'adyen' }

      it 'enqueues a job to create a gocardless payment' do
        expect { create_service.call_async }
          .to have_enqueued_job(Invoices::Payments::CreateJob)
          .with(invoice:, payment_provider: :adyen)
      end
    end
  end
end
