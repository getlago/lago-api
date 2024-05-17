# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::Payments::StripeService, type: :service do
  subject(:stripe_service) { described_class.new(invoice) }

  let(:customer) { create(:customer, payment_provider_code: code) }
  let(:organization) { customer.organization }
  let(:stripe_payment_provider) { create(:stripe_provider, organization:, code:) }
  let(:stripe_customer) { create(:stripe_customer, customer:, payment_method_id: 'pm_123456') }
  let(:code) { 'stripe_1' }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 200,
      currency: 'EUR',
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

    let(:customer_response) do
      File.read(Rails.root.join('spec/fixtures/stripe/customer_retrieve_response.json'))
    end

    let(:payment_status) { 'succeeded' }

    before do
      stripe_payment_provider
      stripe_customer

      allow(Stripe::PaymentIntent).to receive(:create)
        .and_return(
          Stripe::PaymentIntent.construct_from(
            id: 'ch_123456',
            status: payment_status,
            amount: invoice.total_amount_cents,
            currency: invoice.currency,
          ),
        )
      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::PrepaidCreditJob).to receive(:perform_later)

      allow(PaymentProviderCustomers::StripeService).to receive(:new)
        .and_return(provider_customer_service)
      allow(provider_customer_service).to receive(:check_payment_method)
        .and_return(provider_customer_service_result)

      stub_request(:get, "https://api.stripe.com/v1/customers/#{stripe_customer.provider_customer_id}")
        .to_return(status: 200, body: customer_response, headers: {})
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
        expect(result.payment.amount_currency).to eq(invoice.currency)
        expect(result.payment.status).to eq('succeeded')
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
          organization:,
          customer:,
          total_amount_cents: 0,
          currency: 'EUR',
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
      let(:stripe_customer) { create(:stripe_customer, customer:) }

      before do
        allow(Stripe::Customer).to receive(:retrieve)
          .and_return(Stripe::StripeObject.construct_from(
            {
              invoice_settings: {
                default_payment_method: nil
              },
              default_source: nil
            },
          ))

        allow(Stripe::PaymentMethod).to receive(:list)
          .and_return(Stripe::ListObject.construct_from(
            data: [
              {
                id: 'pm_123456',
                object: 'payment_method',
                card: {brand: 'visa'},
                created: 1_656_422_973,
                customer: 'cus_123456',
                livemode: false,
                metadata: {},
                type: 'card'
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
      let(:customer) { create(:customer, organization:, payment_provider_code: code) }

      let(:subscription) do
        create(:subscription, organization:, customer:)
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
        stripe_service.create

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            'invoice.payment_failure',
            invoice,
            provider_customer_id: stripe_customer.provider_customer_id,
            provider_error: {
              message: 'error',
              error_code: nil
            },
          )
      end
    end

    context 'when invoice has a too small amount' do
      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }
      let(:subscription) { create(:subscription, organization:, customer:) }

      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          total_amount_cents: 20,
          currency: 'EUR',
          ready_for_payment_processing: true,
        )
      end

      before do
        subscription

        allow(Stripe::PaymentIntent).to receive(:create)
          .and_raise(Stripe::InvalidRequestError.new('amount_too_small', {}, code: 'amount_too_small'))
      end

      it 'does not send mark the invoice as failed' do
        stripe_service.create
        invoice.reload

        expect(invoice).to be_pending
      end
    end

    context 'when payment status is processing' do
      let(:payment_status) { 'processing' }

      it 'creates a stripe payment and a payment' do
        result = stripe_service.create

        expect(result).to be_success

        aggregate_failures do
          expect(result.invoice).to be_pending
          expect(result.invoice.payment_attempts).to eq(1)
          expect(result.invoice.ready_for_payment_processing).to eq(false)

          expect(result.payment.id).to be_present
          expect(result.payment.invoice).to eq(invoice)
          expect(result.payment.payment_provider).to eq(stripe_payment_provider)
          expect(result.payment.payment_provider_customer).to eq(stripe_customer)
          expect(result.payment.amount_cents).to eq(invoice.total_amount_cents)
          expect(result.payment.amount_currency).to eq(invoice.currency)
          expect(result.payment.status).to eq('processing')
        end

        expect(Stripe::PaymentIntent).to have_received(:create)
      end
    end
  end

  describe '#generate_payment_url' do
    before do
      stripe_payment_provider
      stripe_customer

      allow(Stripe::Checkout::Session).to receive(:create)
        .and_return({'url' => 'https://example.com'})
    end

    it 'generates payment url' do
      stripe_service.generate_payment_url

      expect(Stripe::Checkout::Session).to have_received(:create)
    end

    context 'when invoice is succeeded' do
      before { invoice.succeeded! }

      it 'does not generate payment url' do
        stripe_service.generate_payment_url

        expect(Stripe::Checkout::Session).not_to have_received(:create)
      end
    end

    context 'when invoice is voided' do
      before { invoice.voided! }

      it 'does not generate payment url' do
        stripe_service.generate_payment_url

        expect(Stripe::Checkout::Session).not_to have_received(:create)
      end
    end
  end

  describe '.update_payment_status' do
    let(:payment) do
      create(
        :payment,
        invoice:,
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
        organization_id: organization.id,
        provider_payment_id: 'ch_123456',
        status: 'succeeded',
      )

      expect(result).to be_success
      expect(result.payment.status).to eq('succeeded')
      expect(result.invoice.reload).to have_attributes(
        payment_status: 'succeeded',
        ready_for_payment_processing: false,
      )
    end

    context 'when status is failed' do
      it 'updates the payment and invoice status' do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          provider_payment_id: 'ch_123456',
          status: 'failed',
        )

        expect(result).to be_success
        expect(result.payment.status).to eq('failed')
        expect(result.invoice.reload).to have_attributes(
          payment_status: 'failed',
          ready_for_payment_processing: true,
        )
      end
    end

    context 'when invoice is already succeeded' do
      before { invoice.succeeded! }

      it 'does not update the status of invoice and payment' do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
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
          organization_id: organization.id,
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

    context 'when payment is not found and it is one time payment' do
      let(:payment) { nil }

      before do
        stripe_payment_provider
        stripe_customer
      end

      it 'creates a payment and updates invoice payment status' do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          provider_payment_id: 'ch_123456',
          status: 'succeeded',
          metadata: {lago_invoice_id: invoice.id, payment_type: 'one-time'},
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.payment.status).to eq('succeeded')
          expect(result.invoice.reload).to have_attributes(
            payment_status: 'succeeded',
            ready_for_payment_processing: false,
          )
        end
      end
    end

    context 'when payment is not found' do
      let(:payment) { nil }

      it 'returns an empty result' do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          provider_payment_id: 'ch_123456',
          status: 'succeeded',
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.payment).to be_nil
        end
      end

      context 'with invoice id in metadata' do
        it 'returns an empty result' do
          result = stripe_service.update_payment_status(
            organization_id: organization.id,
            provider_payment_id: 'ch_123456',
            status: 'succeeded',
            metadata: {lago_invoice_id: SecureRandom.uuid},
          )

          aggregate_failures do
            expect(result).to be_success
            expect(result.payment).to be_nil
          end
        end

        context 'when the invoice is found for organization' do
          it 'returns a not found failure' do
            result = stripe_service.update_payment_status(
              organization_id: organization.id,
              provider_payment_id: 'ch_123456',
              status: 'succeeded',
              metadata: {lago_invoice_id: invoice.id},
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
end
