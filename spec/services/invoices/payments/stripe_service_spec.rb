# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::Payments::StripeService, type: :service do
  subject(:stripe_service) { described_class.new(invoice) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:stripe_payment_provider) { create(:stripe_provider, organization: organization) }
  let(:stripe_customer) { create(:stripe_customer, customer: customer, payment_method_id: 'pm_123456') }

  let(:invoice) do
    create(
      :invoice,
      customer: customer,
      total_amount_cents: 200,
      total_amount_currency: 'EUR',
      ready_for_payment_processing: true,
    )
  end

  describe '.create' do
    let(:provider_customer_service) { instance_double(PaymentProviderCustomers::StripeService) }
    let(:provider_customer_service_result) do
      BaseService::Result.new.tap do |result|
        result.payment_method = Stripe::PaymentMethod.new(id: 'pm_123456')
      end
    end

    before do
      stripe_payment_provider
      stripe_customer

      allow(Stripe::PaymentIntent).to receive(:create)
        .and_return(
          Stripe::PaymentIntent.construct_from(
            id: 'ch_123456',
            status: 'succeeded',
            amount: invoice.total_amount_cents,
            currency: invoice.total_amount_currency,
          ),
        )
      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::PrepaidCreditJob).to receive(:perform_later)

      allow(PaymentProviderCustomers::StripeService).to receive(:new)
        .and_return(provider_customer_service)
      allow(provider_customer_service).to receive(:check_payment_method)
        .and_return(provider_customer_service_result)
    end

    it 'creates a stripe payment and a payment' do
      result = stripe_service.create

      expect(result).to be_success

      aggregate_failures do
        expect(result.invoice).to be_succeeded
        expect(result.invoice.payment_attempts).to eq(1)
        expect(result.invoice.ready_for_payment_processing).to eq(false)

        expect(result.payment.id).to be_present
        expect(result.payment.invoice).to eq(invoice)
        expect(result.payment.payment_provider).to eq(stripe_payment_provider)
        expect(result.payment.payment_provider_customer).to eq(stripe_customer)
        expect(result.payment.amount_cents).to eq(invoice.total_amount_cents)
        expect(result.payment.amount_currency).to eq(invoice.total_amount_currency)
        expect(result.payment.status).to eq('succeeded')
      end

      expect(Stripe::PaymentIntent).to have_received(:create)
    end

    context 'when invoice type is credit and new status is succeeded' do
      let(:subscription) { create(:subscription, customer: customer) }
      let(:wallet) { create(:wallet, customer: customer, balance: 10.0, credits_balance: 10.0) }
      let(:wallet_transaction) do
        create(:wallet_transaction, wallet: wallet, amount: 15.0, credit_amount: 15.0, status: 'pending')
      end
      let(:fee) do
        create(
          :fee,
          fee_type: 'credit',
          invoiceable_type: 'WalletTransaction',
          invoiceable_id: wallet_transaction.id,
          invoice: invoice,
        )
      end

      before do
        wallet_transaction
        fee
        subscription
        invoice.update(invoice_type: 'credit')
      end

      it 'calls Invoices::PrepaidCreditJob' do
        stripe_service.create

        expect(Invoices::PrepaidCreditJob).to have_received(:perform_later).with(invoice)
      end
    end

    it 'calls SegmentTrackJob' do
      invoice = stripe_service.create.payment.invoice

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'payment_status_changed',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          payment_status: invoice.payment_status,
        },
      )
    end

    context 'with no payment provider' do
      let(:stripe_payment_provider) { nil }

      it 'does not creates a stripe payment' do
        result = stripe_service.create

        expect(result).to be_success

        aggregate_failures do
          expect(result.invoice).to eq(invoice)
          expect(result.payment).to be_nil

          expect(Stripe::PaymentIntent).not_to have_received(:create)
        end
      end
    end

    context 'with 0 amount' do
      let(:invoice) do
        create(
          :invoice,
          customer: customer,
          total_amount_cents: 0,
          total_amount_currency: 'EUR',
        )
      end

      it 'does not creates a stripe payment' do
        result = stripe_service.create

        expect(result).to be_success

        aggregate_failures do
          expect(result.invoice).to eq(invoice)
          expect(result.payment).to be_nil

          expect(result.invoice).to be_succeeded

          expect(Stripe::PaymentIntent).not_to have_received(:create)
        end
      end
    end

    context 'when customer does not have a provider customer id' do
      before { stripe_customer.update!(provider_customer_id: nil) }

      it 'does not creates a stripe payment' do
        result = stripe_service.create

        expect(result).to be_success

        aggregate_failures do
          expect(result.invoice).to eq(invoice)
          expect(result.payment).to be_nil

          expect(Stripe::PaymentIntent).not_to have_received(:create)
        end
      end
    end

    context 'when customer does not have a payment method' do
      let(:stripe_customer) { create(:stripe_customer, customer: customer) }

      before do
        allow(Stripe::PaymentMethod).to receive(:list)
          .and_return(Stripe::ListObject.construct_from(
            data: [
              {
                id: 'pm_123456',
                object: 'payment_method',
                card: { 'brand': 'visa' },
                created: 1_656_422_973,
                customer: 'cus_123456',
                livemode: false,
                metadata: {},
                type: 'card',
              },
            ],
          ))
      end

      it 'retrieves the payment method' do
        result = stripe_service.create

        expect(result).to be_success
        expect(customer.stripe_customer.reload).to be_present
        expect(customer.stripe_customer.provider_customer_id).to eq(stripe_customer.provider_customer_id)
        expect(customer.stripe_customer.payment_method_id).to eq('pm_123456')

        expect(Stripe::PaymentMethod).to have_received(:list)
        expect(Stripe::PaymentIntent).to have_received(:create)
      end
    end

    context 'with card error on stripe' do
      let(:customer) { create(:customer, organization: organization) }

      let(:subscription) do
        create(:subscription, organization: organization, customer: customer)
      end

      let(:organization) do
        create(:organization, webhook_url: 'https://webhook.com')
      end

      before do
        subscription

        allow(Stripe::PaymentIntent).to receive(:create)
          .and_raise(Stripe::CardError.new('error', {}))
      end

      it 'delivers an error webhook' do
        expect { stripe_service.create }
          .to raise_error(Stripe::CardError)

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            :payment_provider_invoice_payment_error,
            invoice,
            provider_customer_id: stripe_customer.provider_customer_id,
            provider_error: {
              message: 'error',
              error_code: nil,
            },
          )
      end
    end
  end

  describe '.update_payment_status' do
    let(:payment) do
      create(
        :payment,
        invoice: invoice,
        provider_payment_id: 'ch_123456',
      )
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
      allow(SendWebhookJob).to receive(:perform_later)
      payment
    end

    it 'updates the payment and invoice status' do
      result = stripe_service.update_payment_status(
        provider_payment_id: 'ch_123456',
        status: 'succeeded',
      )

      expect(result).to be_success
      expect(result.payment.status).to eq('succeeded')
      expect(result.invoice.payment_status).to eq('succeeded')
      expect(result.invoice.ready_for_payment_processing).to eq(false)
    end

    it 'calls SegmentTrackJob' do
      invoice = stripe_service.update_payment_status(
        provider_payment_id: 'ch_123456',
        status: 'succeeded',
      ).payment.invoice

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'payment_status_changed',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          payment_status: invoice.payment_status,
        },
      )
    end

    it 'calls the SendWebhook job' do
      invoice = stripe_service.update_payment_status(
        provider_payment_id: 'ch_123456',
        status: 'succeeded',
      ).payment.invoice

      expect(SendWebhookJob).to have_received(:perform_later).with(
        'invoice.payment_status_updated',
        invoice,
      )
    end

    context 'when status is failed' do
      it 'updates the payment and invoice status' do
        result = stripe_service.update_payment_status(
          provider_payment_id: 'ch_123456',
          status: 'failed',
        )

        expect(result).to be_success
        expect(result.payment.status).to eq('failed')
        expect(result.invoice.payment_status).to eq('failed')
        expect(result.invoice.ready_for_payment_processing).to eq(true)
      end
    end

    context 'when invoice is already succeeded' do
      before { invoice.succeeded! }

      it 'does not update the status of invoice and payment' do
        result = stripe_service.update_payment_status(
          provider_payment_id: 'ch_123456',
          status: 'succeeded',
        )

        expect(result).to be_success
        expect(result.invoice.payment_status).to eq('succeeded')
      end
    end

    context 'with invalid status' do
      it 'does not update the status of invoice and payment' do
        result = stripe_service.update_payment_status(
          provider_payment_id: 'ch_123456',
          status: 'foo-bar',
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:payment_status)
          expect(result.error.messages[:payment_status]).to include('value_is_invalid')
        end
      end
    end

    context 'when payment is not found' do
      let(:payment) { nil }

      it 'returns an empty result' do
        result = stripe_service.update_payment_status(
          provider_payment_id: 'ch_123456',
          status: 'succeeded',
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.payment).to be_nil
        end
      end

      context 'with invoice id in metadata' do
        it 'returns a not found failure' do
          result = stripe_service.update_payment_status(
            provider_payment_id: 'ch_123456',
            status: 'succeeded',
            metadata: { lago_invoice_id: SecureRandom.uuid },
          )

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq('stripe_payment_not_found')
          end
        end
      end
    end
  end
end
