# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviderCustomers::StripeService, type: :service do
  subject(:stripe_service) { described_class.new(stripe_customer) }

  let(:customer) { create(:customer, organization: organization) }
  let(:stripe_provider) { create(:stripe_provider) }
  let(:organization) { stripe_provider.organization }

  let(:stripe_customer) do
    create(:stripe_customer, customer: customer, provider_customer_id: nil)
  end

  describe '.create' do
    it 'creates the stripe customer' do
      allow(Stripe::Customer).to receive(:create)
        .and_return(Stripe::Customer.new(id: 'cus_123456'))

      result = stripe_service.create

      expect(Stripe::Customer).to have_received(:create)

      expect(result.stripe_customer.provider_customer_id).to eq('cus_123456')
    end

    it 'delivers a success webhook' do
      allow(Stripe::Customer).to receive(:create)
        .and_return(Stripe::Customer.new(id: 'cus_123456'))

      stripe_service.create

      expect(Stripe::Customer).to have_received(:create)

      expect(SendWebhookJob).to have_been_enqueued
        .with('customer.payment_provider_created', customer)
    end

    context 'when customer already have a stripe customer id' do
      let(:stripe_customer) do
        create(:stripe_customer, customer: customer, provider_customer_id: 'cus_123456')
      end

      it 'does not call stripe API' do
        allow(Stripe::Customer).to receive(:create)

        stripe_service.create

        expect(Stripe::Customer).not_to have_received(:create)
      end
    end

    context 'when failing to create the customer' do
      it 'delivers an error webhook' do
        allow(Stripe::Customer).to receive(:create)
          .and_raise(Stripe::InvalidRequestError.new('error', {}))

        expect { stripe_service.create }
          .to raise_error(Stripe::InvalidRequestError)

        expect(Stripe::Customer).to have_received(:create)

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

  describe '.update_payment_method' do
    subject(:stripe_service) { described_class.new }

    let(:stripe_customer) do
      create(:stripe_customer, customer:, provider_customer_id: 'cus_123456')
    end

    it 'updates the customer payment method' do
      result = stripe_service.update_payment_method(
        organization_id: organization.id,
        stripe_customer_id: stripe_customer.provider_customer_id,
        payment_method_id: 'pm_123456',
      )

      aggregate_failures do
        expect(result).to be_success
        expect(result.stripe_customer.payment_method_id).to eq('pm_123456')
      end
    end

    context 'with pending invoices' do
      let(:invoice) do
        create(
          :invoice,
          customer:,
          total_amount_cents: 200,
          total_amount_currency: 'EUR',
        )
      end

      before { invoice }

      it 'enqueues jobs to reprocess the pending payment' do
        result = stripe_service.update_payment_method(
          organization_id: organization.id,
          stripe_customer_id: stripe_customer.provider_customer_id,
          payment_method_id: 'pm_123456',
        )

        aggregate_failures do
          expect(result).to be_success

          expect(Invoices::Payments::StripeCreateJob).to have_been_enqueued
            .with(invoice)
        end
      end
    end
  end

  describe '.delete_payment_method' do
    subject(:stripe_service) { described_class.new }

    let(:payment_method_id) { 'card_12345' }

    let(:stripe_customer) do
      create(
        :stripe_customer,
        customer: customer,
        provider_customer_id: 'cus_123456',
        payment_method_id: payment_method_id,
      )
    end

    it 'removes the customer payment method' do
      result = stripe_service.delete_payment_method(
        organization_id: organization.id,
        stripe_customer_id: stripe_customer.provider_customer_id,
        payment_method_id: payment_method_id,
      )

      aggregate_failures do
        expect(result).to be_success
        expect(result.stripe_customer.payment_method_id).to be_nil
      end
    end

    context 'when customer payment method is not the deleted one' do
      it 'does not remove the customer payment method' do
        result = stripe_service.delete_payment_method(
          organization_id: organization.id,
          stripe_customer_id: stripe_customer.provider_customer_id,
          payment_method_id: 'other_payment_method_id',
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.stripe_customer.payment_method_id).to eq(payment_method_id)
        end
      end
    end
  end

  describe '.check_payment_method' do
    let(:payment_method_id) { 'card_12345' }

    let(:stripe_customer) do
      create(
        :stripe_customer,
        customer: customer,
        provider_customer_id: 'cus_123456',
        payment_method_id: payment_method_id,
      )
    end

    let(:payment_method) { Stripe::PaymentMethod.new(id: payment_method_id) }

    let(:stripe_api_customer) { instance_double(Stripe::Customer) }

    before do
      allow(Stripe::Customer).to receive(:new)
        .and_return(stripe_api_customer)
    end

    it 'checks for the existance of the payment method' do
      allow(stripe_api_customer)
        .to receive(:retrieve_payment_method)
        .and_return(payment_method)

      result = stripe_service.check_payment_method(payment_method_id)

      aggregate_failures do
        expect(result).to be_success
        expect(result.payment_method.id).to eq(payment_method_id)

        expect(Stripe::Customer).to have_received(:new)
        expect(stripe_api_customer).to have_received(:retrieve_payment_method)
      end
    end

    context 'when payment method is not found on stripe' do
      before do
        allow(stripe_api_customer)
          .to receive(:retrieve_payment_method)
          .and_raise(Stripe::InvalidRequestError.new('error', {}))
      end

      it 'returns a failed result' do
        result = stripe_service.check_payment_method(payment_method_id)

        aggregate_failures do
          expect(result).not_to be_success

          expect(Stripe::Customer).to have_received(:new)
          expect(stripe_api_customer).to have_received(:retrieve_payment_method)
        end
      end
    end
  end
end
