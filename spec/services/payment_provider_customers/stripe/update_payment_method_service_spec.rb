# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviderCustomers::Stripe::UpdatePaymentMethodService, type: :service do
  subject(:update_service) { described_class.new(stripe_customer:, payment_method_id:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:stripe_customer) { create(:stripe_customer, customer:) }
  let(:payment_method_id) { 'pm_123456' }

  describe '#call' do
    it 'updates the customer payment method', aggregate_failures: true do
      result = update_service.call

      expect(result).to be_success
      expect(result.stripe_customer.payment_method_id).to eq(payment_method_id)
    end

    context 'with pending invoices' do
      let(:invoice) do
        create(
          :invoice,
          customer:,
          total_amount_cents: 200,
          currency: 'EUR',
          status:,
          ready_for_payment_processing:
        )
      end

      let(:status) { 'finalized' }
      let(:ready_for_payment_processing) { true }

      before { invoice }

      it 'enqueues jobs to reprocess the pending payment', aggregate_failure: true do
        result = update_service.call

        expect(result).to be_success
        expect(Invoices::Payments::StripeCreateJob).to have_been_enqueued
          .with(invoice)
      end

      context 'when invoices are not finalized' do
        let(:status) { 'draft' }

        it 'does not enqueue jobs to reprocess pending payment', aggregate_failure: true do
          result = update_service.call

          expect(result).to be_success
          expect(Invoices::Payments::StripeCreateJob).not_to have_been_enqueued
            .with(invoice)
        end
      end

      context 'when invoices are not ready for payment processing' do
        let(:ready_for_payment_processing) { 'false' }

        it 'does not enqueue jobs to reprocess pending payment', aggregate_failure: true do
          result = update_service.call

          expect(result).to be_success
          expect(Invoices::Payments::StripeCreateJob).not_to have_been_enqueued
            .with(invoice)
        end
      end
    end
  end
end
