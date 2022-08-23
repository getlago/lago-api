# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::PaidCreditService, type: :service do
  subject(:invoice_service) do
    described_class.new(customer: customer, wallet_transaction: wallet_transaction, date: date)
  end
  let(:date) { Time.zone.now.to_date }

  describe 'create' do
    let(:customer) { create(:customer) }
    let(:subscription) { create(:subscription, customer: customer) }
    let(:wallet) { create(:wallet, customer: customer) }
    let(:wallet_transaction) do
      create(:wallet_transaction, wallet: wallet, amount: '15.00', credit_amount: '15.00')
    end

    before do
      wallet_transaction
      subscription
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates an invoice' do
      result = invoice_service.create

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice.issuing_date).to eq(date)
        expect(result.invoice.invoice_type).to eq('credit')
        expect(result.invoice.status).to eq('pending')

        expect(result.invoice.amount_cents).to eq(15)
        expect(result.invoice.amount_currency).to eq('EUR')
        expect(result.invoice.vat_amount_cents).to eq(3)
        expect(result.invoice.vat_amount_currency).to eq('EUR')
        expect(result.invoice.total_amount_cents).to eq(18)
        expect(result.invoice.total_amount_currency).to eq('EUR')
      end
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        invoice_service.create
      end.to have_enqueued_job(SendWebhookJob)
    end

    it 'calls SegmentTrackJob' do
      invoice = invoice_service.create.invoice

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type
        }
      )
    end

    context 'when organization does not have a webhook url' do
      before { customer.organization.update!(webhook_url: nil) }

      it 'does not enqueues a SendWebhookJob' do
        expect do
          invoice_service.create
        end.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when customer payment_provider is stripe' do
      before { customer.update!(payment_provider: 'stripe') }

      it 'enqueue a job to create a payment' do
        expect do
          invoice_service.create
        end.to have_enqueued_job(Invoices::Payments::StripeCreateJob)
      end
    end
  end
end
