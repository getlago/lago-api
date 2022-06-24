# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::Payments::StripeService, type: :service do
  subject(:stripe_service) { described_class.new(invoice) }

  let(:customer) { create(:customer) }
  let(:stripe_payment_provider) { create(:stripe_provider, organization: customer.organization) }
  let(:stripe_customer) { create(:stripe_customer, customer: customer) }

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

      allow(Stripe::Charge).to receive(:create)
        .and_return(
          Stripe::Charge.construct_from(
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

      expect(Stripe::Charge).to have_received(:create)
    end

    context 'with no payment provider' do
      let(:stripe_payment_provider) { nil }

      it 'does not creates a stripe payment' do
        result = stripe_service.create

        expect(result).to be_success

        aggregate_failures do
          expect(result.invoice).to be_nil
          expect(result.payment).to be_nil

          expect(Stripe::Charge).not_to have_received(:create)
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
          expect(result.invoice).to be_nil
          expect(result.payment).to be_nil

          expect(Stripe::Charge).not_to have_received(:create)
        end
      end

      context 'when send_zero_amount_invoice is turned on' do
        let(:stripe_payment_provider) do
          create(
            :stripe_provider,
            organization: customer.organization,
            send_zero_amount_invoice: true,
          )
        end

        it 'creates a stripe payment and a payment' do
          result = stripe_service.create

          expect(result).to be_success

          aggregate_failures do
            expect(result.invoice).to be_pending

            expect(result.payment.id).to be_present
            expect(result.payment.amount_cents).to eq(0)

            expect(Stripe::Charge).to have_received(:create)
          end
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
      end

      it 'creates the customer' do
        result = stripe_service.create

        expect(result).to be_success
        expect(customer.stripe_customer.reload).to be_present
        expect(customer.stripe_customer.provider_customer_id).to eq('cus_123456')

        expect(Stripe::Customer).to have_received(:create)
        expect(Stripe::Charge).to have_received(:create)
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
