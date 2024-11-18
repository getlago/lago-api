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
      ready_for_payment_processing: true
    )
  end

  describe '.call' do
    let(:provider_customer_service) { instance_double(PaymentProviderCustomers::StripeService) }

    let(:provider_customer_service_result) do
      BaseService::Result.new.tap do |result|
        result.payment_method = Stripe::PaymentMethod.new(id: 'pm_123456')
      end
    end

    let(:customer_response) do
      File.read(Rails.root.join('spec/fixtures/stripe/customer_retrieve_response.json'))
    end

    let(:stripe_payment_intent) do
      Stripe::PaymentIntent.construct_from(
        id: 'ch_123456',
        status: payment_status,
        amount: invoice.total_amount_cents,
        currency: invoice.currency
      )
    end

    let(:payment_status) { 'succeeded' }

    before do
      stripe_payment_provider
      stripe_customer

      allow(Stripe::PaymentIntent).to receive(:create)
        .and_return(stripe_payment_intent)
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
      result = stripe_service.call

      expect(result).to be_success

      aggregate_failures do
        expect(result.invoice).to be_payment_succeeded
        expect(result.invoice.payment_attempts).to eq(1)
        expect(result.invoice.ready_for_payment_processing).to eq(false)

        expect(result.payment.id).to be_present
        expect(result.payment.payable).to eq(invoice)
        expect(result.payment.payment_provider).to eq(stripe_payment_provider)
        expect(result.payment.payment_provider_customer).to eq(stripe_customer)
        expect(result.payment.amount_cents).to eq(invoice.total_amount_cents)
        expect(result.payment.amount_currency).to eq(invoice.currency)
        expect(result.payment.status).to eq('succeeded')
      end

      expect(Stripe::PaymentIntent).to have_received(:create)
    end

    it_behaves_like 'syncs payment' do
      let(:service_call) { stripe_service.call }
    end

    context 'with no payment provider' do
      let(:stripe_payment_provider) { nil }

      it 'does not creates a stripe payment' do
        result = stripe_service.call

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
          currency: 'EUR'
        )
      end

      it 'does not creates a stripe payment' do
        result = stripe_service.call

        expect(result).to be_success

        aggregate_failures do
          expect(result.invoice).to eq(invoice)
          expect(result.payment).to be_nil

          expect(result.invoice).to be_payment_succeeded

          expect(Stripe::PaymentIntent).not_to have_received(:create)
        end
      end
    end

    context 'when customer does not have a provider customer id' do
      before { stripe_customer.update!(provider_customer_id: nil) }

      it 'does not creates a stripe payment' do
        result = stripe_service.call

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
            }
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
              }
            ]
          ))
      end

      it 'retrieves the payment method' do
        result = stripe_service.call

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
          .and_raise(::Stripe::CardError.new('error', {}))
      end

      it 'delivers an error webhook' do
        allow(Invoices::Payments::DeliverErrorWebhookService).to receive(:call_async).and_call_original

        stripe_service.call

        expect(Invoices::Payments::DeliverErrorWebhookService).to have_received(:call_async)
        expect(SendWebhookJob).to have_been_enqueued
          .with(
            'invoice.payment_failure',
            invoice,
            provider_customer_id: stripe_customer.provider_customer_id,
            provider_error: {
              message: 'error',
              error_code: nil
            }
          )
      end

      context 'when invoice is credit? and open?' do
        let(:wallet_transaction) { create(:wallet_transaction) }

        before do
          create(:fee, fee_type: :credit, invoice: invoice, invoiceable: wallet_transaction)
          invoice.update! status: :open, invoice_type: :credit
        end

        it 'delivers an error webhook' do
          allow(Invoices::Payments::DeliverErrorWebhookService).to receive(:call_async).and_call_original

          stripe_service.call

          expect(Invoices::Payments::DeliverErrorWebhookService).to have_received(:call_async)
          expect(SendWebhookJob).to have_been_enqueued
            .with(
              'wallet_transaction.payment_failure',
              wallet_transaction,
              provider_customer_id: stripe_customer.provider_customer_id,
              provider_error: {
                message: 'error',
                error_code: nil
              }
            )
        end
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
          ready_for_payment_processing: true
        )
      end

      before do
        subscription

        allow(Stripe::PaymentIntent).to receive(:create)
          .and_raise(::Stripe::InvalidRequestError.new('amount_too_small', {}, code: 'amount_too_small'))
      end

      it 'does not send mark the invoice as failed' do
        stripe_service.call
        invoice.reload

        expect(invoice).to be_payment_pending
      end
    end

    context 'when payment status is processing' do
      let(:payment_status) { 'processing' }

      it 'creates a stripe payment and a payment' do
        result = stripe_service.call

        expect(result).to be_success

        aggregate_failures do
          expect(result.invoice).to be_payment_pending
          expect(result.invoice.payment_attempts).to eq(1)
          expect(result.invoice.ready_for_payment_processing).to eq(false)

          expect(result.payment.id).to be_present
          expect(result.payment.payable).to eq(invoice)
          expect(result.payment.payment_provider).to eq(stripe_payment_provider)
          expect(result.payment.payment_provider_customer).to eq(stripe_customer)
          expect(result.payment.amount_cents).to eq(invoice.total_amount_cents)
          expect(result.payment.amount_currency).to eq(invoice.currency)
          expect(result.payment.status).to eq('processing')
        end

        expect(Stripe::PaymentIntent).to have_received(:create)
      end
    end

    context 'when customers country is IN' do
      let(:payment_status) { 'requires_action' }

      let(:stripe_payment_intent) do
        Stripe::PaymentIntent.construct_from(
          id: 'ch_123456',
          status: payment_status,
          amount: invoice.total_amount_cents,
          currency: invoice.currency,
          next_action: {
            redirect_to_url: {url: 'https://foo.bar'}
          }
        )
      end

      before do
        customer.update(country: 'IN')
      end

      it 'creates a stripe payment and payment with requires_action status' do
        result = stripe_service.call

        expect(result).to be_success

        aggregate_failures do
          expect(result.payment.status).to eq('requires_action')
          expect(result.payment.provider_payment_data).not_to be_empty
        end
      end

      it 'has enqueued a SendWebhookJob' do
        result = stripe_service.call

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            'payment.requires_action',
            result.payment,
            provider_customer_id: stripe_customer.provider_customer_id
          )
      end
    end

    context 'with #payment_intent_payload' do
      let(:payment_intent_payload) { stripe_service.__send__(:payment_intent_payload) }
      let(:payload) do
        {
          amount: invoice.total_amount_cents,
          currency: invoice.currency.downcase,
          customer: customer.stripe_customer.provider_customer_id,
          payment_method: customer.stripe_customer.payment_method_id,
          payment_method_types: customer.stripe_customer.provider_payment_methods,
          confirm: true,
          off_session: true,
          return_url: stripe_service.__send__(:success_redirect_url),
          error_on_requires_action: true,
          description: stripe_service.__send__(:description),
          metadata: {
            lago_customer_id: customer.id,
            lago_invoice_id: invoice.id,
            invoice_issuing_date: invoice.issuing_date.iso8601,
            invoice_type: invoice.invoice_type
          }
        }
      end

      it 'returns the payload' do
        expect(payment_intent_payload).to eq(payload)
      end

      context 'when customers country is IN' do
        before do
          payload[:off_session] = false
          payload[:error_on_requires_action] = false
          customer.update!(country: 'IN')
        end

        it 'returns the payload' do
          expect(payment_intent_payload).to eq(payload)
        end
      end
    end

    context 'with #description' do
      let(:description_call) { stripe_service.__send__(:description) }
      let(:description) { "#{organization.name} - Invoice #{invoice.number}" }

      it 'returns the description' do
        expect(description_call).to eq(description)
      end
    end
  end

  describe '#generate_payment_url' do
    before do
      stripe_payment_provider
      stripe_customer

      allow(::Stripe::Checkout::Session).to receive(:create)
        .and_return({'url' => 'https://example.com'})
    end

    it 'generates payment url' do
      stripe_service.generate_payment_url

      expect(::Stripe::Checkout::Session).to have_received(:create)
    end

    context 'when invoice is payment_succeeded' do
      before { invoice.payment_succeeded! }

      it 'does not generate payment url' do
        stripe_service.generate_payment_url

        expect(::Stripe::Checkout::Session).not_to have_received(:create)
      end
    end

    context 'when invoice is voided' do
      before { invoice.voided! }

      it 'does not generate payment url' do
        stripe_service.generate_payment_url

        expect(::Stripe::Checkout::Session).not_to have_received(:create)
      end
    end

    context 'with #payment_url_payload' do
      let(:payment_url_payload) { stripe_service.__send__(:payment_url_payload) }
      let(:payload) do
        {
          line_items: [
            {
              quantity: 1,
              price_data: {
                currency: invoice.currency.downcase,
                unit_amount: invoice.total_amount_cents,
                product_data: {
                  name: invoice.number
                }
              }
            }
          ],
          mode: 'payment',
          success_url: stripe_service.__send__(:success_redirect_url),
          customer: customer.stripe_customer.provider_customer_id,
          payment_method_types: customer.stripe_customer.provider_payment_methods,
          payment_intent_data: {
            description: stripe_service.__send__(:description),
            metadata: {
              lago_customer_id: customer.id,
              lago_invoice_id: invoice.id,
              invoice_issuing_date: invoice.issuing_date.iso8601,
              invoice_type: invoice.invoice_type,
              payment_type: 'one-time'
            }
          }
        }
      end

      it 'returns the payload' do
        expect(payment_url_payload).to eq(payload)
      end
    end
  end

  describe '.update_payment_status' do
    let(:payment) do
      create(
        :payment,
        payable: invoice,
        provider_payment_id: 'ch_123456'
      )
    end

    let(:stripe_payment) do
      PaymentProviders::StripeProvider::StripePayment.new(
        id: 'ch_123456',
        status: 'succeeded',
        metadata: {}
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
        status: 'succeeded',
        stripe_payment:
      )

      expect(result).to be_success
      expect(result.payment.status).to eq('succeeded')
      expect(result.invoice.reload).to have_attributes(
        payment_status: 'succeeded',
        ready_for_payment_processing: false
      )
    end

    context 'when status is failed' do
      let(:stripe_payment) do
        PaymentProviders::StripeProvider::StripePayment.new(
          id: 'ch_123456',
          status: 'canceled',
          metadata: {}
        )
      end

      it 'updates the payment and invoice status' do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          status: 'failed',
          stripe_payment:
        )

        expect(result).to be_success
        expect(result.payment.status).to eq('failed')
        expect(result.invoice.reload).to have_attributes(
          payment_status: 'failed',
          ready_for_payment_processing: true
        )
      end
    end

    context 'when invoice is already payment_succeeded' do
      before { invoice.payment_succeeded! }

      it 'does not update the status of invoice and payment' do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          status: 'succeeded',
          stripe_payment:
        )

        expect(result).to be_success
        expect(result.invoice.payment_status).to eq('succeeded')
      end
    end

    context 'with invalid status' do
      it 'does not update the status of invoice and payment' do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          status: 'foo-bar',
          stripe_payment:
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

      let(:stripe_payment) do
        PaymentProviders::StripeProvider::StripePayment.new(
          id: 'ch_123456',
          status: 'succeeded',
          metadata: {lago_invoice_id: invoice.id, payment_type: 'one-time'}
        )
      end

      before do
        stripe_payment_provider
        stripe_customer
      end

      it 'creates a payment and updates invoice payment status' do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          status: 'succeeded',
          stripe_payment:
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.payment.status).to eq('succeeded')
          expect(result.invoice.reload).to have_attributes(
            payment_status: 'succeeded',
            ready_for_payment_processing: false
          )
        end
      end

      context 'when invoice is not found' do
        let(:stripe_payment) do
          PaymentProviders::StripeProvider::StripePayment.new(
            id: 'ch_123456',
            status: 'succeeded',
            metadata: {lago_invoice_id: 'invalid', payment_type: 'one-time'}
          )
        end

        it 'raises a not found failure' do
          result = stripe_service.update_payment_status(
            organization_id: organization.id,
            status: 'succeeded',
            stripe_payment:
          )

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq('invoice_not_found')
          end
        end
      end
    end

    context 'when payment is not found' do
      let(:payment) { nil }

      it 'returns an empty result' do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          status: 'succeeded',
          stripe_payment:
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.payment).to be_nil
        end
      end

      context 'with invoice id in metadata' do
        let(:stripe_payment) do
          PaymentProviders::StripeProvider::StripePayment.new(
            id: 'ch_123456',
            status: 'succeeded',
            metadata: {lago_invoice_id: SecureRandom.uuid}
          )
        end

        it 'returns an empty result' do
          result = stripe_service.update_payment_status(
            organization_id: organization.id,
            status: 'succeeded',
            stripe_payment:
          )

          aggregate_failures do
            expect(result).to be_success
            expect(result.payment).to be_nil
          end
        end

        context 'when the invoice is found for organization' do
          let(:stripe_payment) do
            PaymentProviders::StripeProvider::StripePayment.new(
              id: 'ch_123456',
              status: 'succeeded',
              metadata: {lago_invoice_id: invoice.id}
            )
          end

          before do
            stripe_customer
            stripe_payment_provider
          end

          it 'creates the missing payment and updates invoice status' do
            result = stripe_service.update_payment_status(
              organization_id: organization.id,
              status: 'succeeded',
              stripe_payment:
            )

            expect(result).to be_success
            expect(result.payment.status).to eq('succeeded')
            expect(result.invoice.reload).to have_attributes(
              payment_status: 'succeeded',
              ready_for_payment_processing: false
            )

            expect(invoice.payments.count).to eq(1)
            payment = invoice.payments.first
            expect(payment).to have_attributes(
              payable: invoice,
              payment_provider_id: stripe_payment_provider.id,
              payment_provider_customer_id: stripe_customer.id,
              amount_cents: invoice.total_amount_cents,
              amount_currency: invoice.currency,
              provider_payment_id: 'ch_123456',
              status: 'succeeded'
            )
          end
        end
      end
    end
  end
end
