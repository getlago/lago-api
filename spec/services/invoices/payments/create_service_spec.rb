# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::Payments::CreateService, type: :service do
  subject(:create_service) { described_class.new(invoice:, payment_provider:) }

  let(:invoice) { create(:invoice, customer:, organization: customer.organization) }
  let(:customer) { create(:customer, payment_provider:) }
  let(:payment_provider) { 'stripe' }

  describe '#call' do
    let(:result) { BaseService::Result.new }

    it 'calls the stripe service' do
      allow(Invoices::Payments::StripeService)
        .to receive(:call).with(invoice)
        .and_return(result)

      create_service.call

      expect(Invoices::Payments::StripeService).to have_received(:call).with(invoice)
    end

    context 'with gocardless payment provider' do
      let(:payment_provider) { 'gocardless' }

      it 'calls the gocardless service' do
        allow(Invoices::Payments::GocardlessService)
          .to receive(:call).with(invoice)
          .and_return(result)

        create_service.call

        expect(Invoices::Payments::GocardlessService).to have_received(:call).with(invoice)
      end
    end

    context 'with adyen payment provider' do
      let(:payment_provider) { 'adyen' }

      it 'calls the adyen service' do
        allow(Invoices::Payments::AdyenService)
          .to receive(:call).with(invoice)
          .and_return(result)

        create_service.call

        expect(Invoices::Payments::AdyenService).to have_received(:call).with(invoice)
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
      let(:payment_provider) { 'gocardless' }

      it 'enqueues a job to create a gocardless payment' do
        expect { create_service.call_async }
          .to have_enqueued_job(Invoices::Payments::CreateJob)
          .with(invoice:, payment_provider: :gocardless)
      end
    end

    context 'with adyen payment provider' do
      let(:payment_provider) { 'adyen' }

      it 'enqueues a job to create a gocardless payment' do
        expect { create_service.call_async }
          .to have_enqueued_job(Invoices::Payments::CreateJob)
          .with(invoice:, payment_provider: :adyen)
      end
    end
  end
end
