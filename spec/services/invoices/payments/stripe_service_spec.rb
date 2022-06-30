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
    )
  end

  describe '.create' do
    before do
      stripe_payment_provider
      stripe_customer

      allow(Stripe::PaymentIntent).to receive(:create)
        .and_return(
          Stripe::PaymentIntent.construct_from(
            id: 'ch_123456',
            status: 'pending',
            amount: invoice.total_amount_cents,
            currency: invoice.total_amount_currency,
          ),
        )
    end

    it 'creates a stripe payment and a payment' do
      result = stripe_service.create

      expect(result).to be_success

      aggregate_failures do
        expect(result.invoice).to be_pending

        expect(result.payment.id).to be_present
        expect(result.payment.invoice).to eq(invoice)
        expect(result.payment.payment_provider).to eq(stripe_payment_provider)
        expect(result.payment.payment_provider_customer).to eq(stripe_customer)
        expect(result.payment.amount_cents).to eq(invoice.total_amount_cents)
        expect(result.payment.amount_currency).to eq(invoice.total_amount_currency)
        expect(result.payment.status).to eq('pending')
      end

      expect(Stripe::PaymentIntent).to have_received(:create)
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
      let(:stripe_customer) {}

      before do
        allow(Stripe::Customer).to receive(:create)
          .and_return(
            Stripe::Customer.construct_from(
              id: 'cus_123456',
            ),
          )

        allow(Stripe::PaymentMethod).to receive(:list)
          .and_return(Stripe::ListObject.construct_from(data: []))
      end

      it 'creates the customer' do
        result = stripe_service.create

        expect(result).to be_success
        expect(customer.stripe_customer.reload).to be_present
        expect(customer.stripe_customer.provider_customer_id).to eq('cus_123456')

        expect(Stripe::Customer).to have_received(:create)
        expect(Stripe::PaymentMethod).to have_received(:list)
        expect(Stripe::PaymentIntent).to have_received(:create)
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

  describe '.update_status' do
    let(:payment) do
      create(
        :payment,
        invoice: invoice,
        provider_payment_id: 'ch_123456',
      )
    end

    before { payment }

    it 'updates the payment and invoice status' do
      result = stripe_service.update_status(
        provider_payment_id: 'ch_123456',
        status: 'succeeded',
      )

      expect(result).to be_success
      expect(result.payment.status).to eq('succeeded')
      expect(result.invoice.status).to eq('succeeded')
    end

    context 'when invoice is already succeeded' do
      before { invoice.succeeded! }

      it 'does not update the status of invoice and payment' do
        result = stripe_service.update_status(
          provider_payment_id: 'ch_123456',
          status: 'succeeded',
        )

        expect(result).to be_success
        expect(result.invoice.status).to eq('succeeded')
      end
    end

    context 'with invalid status' do
      it 'does not update the status of invoice and payment' do
        result = stripe_service.update_status(
          provider_payment_id: 'ch_123456',
          status: 'foo-bar',
        )

        expect(result).not_to be_success
        expect(result.error_code).to eq('invalid_invoice_status')
      end
    end
  end
end
