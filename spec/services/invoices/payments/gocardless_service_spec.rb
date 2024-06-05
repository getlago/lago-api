# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::Payments::GocardlessService, type: :service do
  subject(:gocardless_service) { described_class.new(argument) }

  let(:customer) { create(:customer, payment_provider_code: code) }
  let(:organization) { customer.organization }
  let(:gocardless_payment_provider) { create(:gocardless_provider, organization:, code:) }
  let(:gocardless_customer) { create(:gocardless_customer, customer:) }
  let(:gocardless_client) { instance_double(GoCardlessPro::Client) }
  let(:gocardless_payments_service) { instance_double(GoCardlessPro::Services::PaymentsService) }
  let(:gocardless_mandates_service) { instance_double(GoCardlessPro::Services::MandatesService) }
  let(:gocardless_list_response) { instance_double(GoCardlessPro::ListResponse) }
  let(:argument) { invoice }
  let(:code) { 'gocardless_1' }

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

  describe '.create' do
    before do
      gocardless_payment_provider
      gocardless_customer

      allow(GoCardlessPro::Client).to receive(:new)
        .and_return(gocardless_client)
      allow(gocardless_client).to receive(:mandates)
        .and_return(gocardless_mandates_service)
      allow(gocardless_mandates_service).to receive(:list)
        .and_return(gocardless_list_response)
      allow(gocardless_list_response).to receive(:records)
        .and_return([GoCardlessPro::Resources::Mandate.new('id' => 'mandate_id')])
      allow(gocardless_client).to receive(:payments)
        .and_return(gocardless_payments_service)
      allow(gocardless_payments_service).to receive(:create)
        .and_return(GoCardlessPro::Resources::Payment.new(
          'id' => '_ID_',
          'amount' => invoice.total_amount_cents,
          'currency' => invoice.currency,
          'status' => 'paid_out'
        ))
      allow(Invoices::PrepaidCreditJob).to receive(:perform_later)
    end

    it 'creates a gocardless payment' do
      result = gocardless_service.create

      expect(result).to be_success

      aggregate_failures do
        expect(result.invoice).to be_succeeded
        expect(result.invoice.payment_attempts).to eq(1)
        expect(result.invoice.reload.ready_for_payment_processing).to eq(false)

        expect(result.payment.id).to be_present
        expect(result.payment.invoice).to eq(invoice)
        expect(result.payment.payment_provider).to eq(gocardless_payment_provider)
        expect(result.payment.payment_provider_customer).to eq(gocardless_customer)
        expect(result.payment.amount_cents).to eq(invoice.total_amount_cents)
        expect(result.payment.amount_currency).to eq(invoice.currency)
        expect(result.payment.status).to eq('paid_out')
        expect(gocardless_customer.reload.provider_mandate_id).to eq('mandate_id')
      end

      expect(gocardless_payments_service).to have_received(:create)
    end

    it_behaves_like 'syncs payment' do
      let(:service_call) { gocardless_service.create }
    end

    context 'with no payment provider' do
      let(:gocardless_payment_provider) { nil }

      it 'does not creates a gocardless payment' do
        result = gocardless_service.create

        expect(result).to be_success

        aggregate_failures do
          expect(result.invoice).to eq(invoice)
          expect(result.payment).to be_nil

          expect(gocardless_payments_service).not_to have_received(:create)
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

      it 'does not creates a gocardless payment' do
        result = gocardless_service.create

        expect(result).to be_success

        aggregate_failures do
          expect(result.invoice).to eq(invoice)
          expect(result.payment).to be_nil

          expect(result.invoice).to be_succeeded

          expect(gocardless_payments_service).not_to have_received(:create)
        end
      end
    end

    context 'when customer does not have a provider customer id' do
      before { gocardless_customer.update!(provider_customer_id: nil) }

      it 'does not creates a gocardless payment' do
        result = gocardless_service.create

        expect(result).to be_success

        aggregate_failures do
          expect(result.invoice).to eq(invoice)
          expect(result.payment).to be_nil

          expect(gocardless_payments_service).not_to have_received(:create)
        end
      end
    end

    context 'with error on gocardless' do
      let(:customer) { create(:customer, organization:, payment_provider_code: code) }

      let(:subscription) do
        create(:subscription, organization:, customer:)
      end

      let(:organization) do
        create(:organization, webhook_url: 'https://webhook.com')
      end

      before do
        subscription

        allow(gocardless_payments_service).to receive(:create)
          .and_raise(GoCardlessPro::Error.new('code' => 'code', 'message' => 'error'))
      end

      it 'delivers an error webhook' do
        expect { gocardless_service.create }
          .to raise_error(GoCardlessPro::Error)

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            'invoice.payment_failure',
            invoice,
            provider_customer_id: gocardless_customer.provider_customer_id,
            provider_error: {
              message: 'error',
              error_code: 'code'
            }
          )
      end
    end
  end

  describe '.update_payment_status' do
    let(:payment) do
      create(
        :payment,
        invoice:,
        provider_payment_id: 'ch_123456',
        status: 'pending_submission'
      )
    end

    before do
      allow(SendWebhookJob).to receive(:perform_later)
      payment
    end

    it 'updates the payment and invoice payment_status' do
      result = gocardless_service.update_payment_status(
        provider_payment_id: 'ch_123456',
        status: 'paid_out'
      )

      expect(result).to be_success
      expect(result.payment.status).to eq('paid_out')
      expect(result.invoice.reload).to have_attributes(
        payment_status: 'succeeded',
        ready_for_payment_processing: false
      )
    end

    context 'when status is failed' do
      it 'updates the payment and invoice status' do
        result = gocardless_service.update_payment_status(
          provider_payment_id: 'ch_123456',
          status: 'failed'
        )

        expect(result).to be_success
        expect(result.payment.status).to eq('failed')
        expect(result.invoice.reload).to have_attributes(
          payment_status: 'failed',
          ready_for_payment_processing: true
        )
      end
    end

    context 'when invoice is already succeeded' do
      before { invoice.succeeded! }

      it 'does not update the status of invoice and payment' do
        result = gocardless_service.update_payment_status(
          provider_payment_id: 'ch_123456',
          status: 'paid_out'
        )

        expect(result).to be_success
        expect(result.invoice.payment_status).to eq('succeeded')
      end
    end

    context 'with invalid status' do
      it 'does not update the payment_status of invoice' do
        result = gocardless_service.update_payment_status(
          provider_payment_id: 'ch_123456',
          status: 'foo-bar'
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:payment_status)
          expect(result.error.messages[:payment_status]).to include('value_is_invalid')
        end
      end
    end

    context 'when invoice is not passed to constructor' do
      let(:argument) { nil }

      it 'updates the payment and invoice payment_status' do
        result = gocardless_service.update_payment_status(
          provider_payment_id: 'ch_123456',
          status: 'paid_out'
        )

        expect(result).to be_success
        expect(result.payment.status).to eq('paid_out')
        expect(result.invoice.reload).to have_attributes(
          payment_status: 'succeeded',
          ready_for_payment_processing: false
        )
      end
    end
  end
end
