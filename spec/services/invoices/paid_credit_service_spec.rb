# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::PaidCreditService, type: :service do
  subject(:invoice_service) do
    described_class.new(wallet_transaction: wallet_transaction, timestamp: timestamp)
  end

  let(:timestamp) { Time.current.to_i }

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

        expect(result.invoice.issuing_date).to eq(Time.zone.at(timestamp).to_date)
        expect(result.invoice.invoice_type).to eq('credit')
        expect(result.invoice.payment_status).to eq('pending')

        expect(result.invoice.amount_cents).to eq(1500)
        expect(result.invoice.amount_currency).to eq('EUR')
        expect(result.invoice.vat_amount_cents).to eq(300)
        expect(result.invoice.vat_amount_currency).to eq('EUR')
        expect(result.invoice.vat_rate).to eq(20)
        expect(result.invoice.total_amount_cents).to eq(1800)
        expect(result.invoice.total_amount_currency).to eq('EUR')

        expect(result.invoice).to be_legacy
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
          invoice_type: invoice.invoice_type,
        },
      )
    end

    it 'creates a payment' do
      payment_create_service = instance_double(Invoices::Payments::CreateService)
      allow(Invoices::Payments::CreateService)
        .to receive(:new).and_return(payment_create_service)
      allow(payment_create_service)
        .to receive(:call)

      invoice_service.create

      expect(Invoices::Payments::CreateService).to have_received(:new)
      expect(payment_create_service).to have_received(:call)
    end

    context 'when organization does not have a webhook url' do
      before { customer.organization.update!(webhook_url: nil) }

      it 'does not enqueues a SendWebhookJob' do
        expect do
          invoice_service.create
        end.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'with customer timezone' do
      before { customer.update!(timezone: 'America/Los_Angeles') }

      let(:timestamp) { DateTime.parse('2022-11-25 01:00:00').to_i }

      it 'assigns the issuing date in the customer timezone' do
        result = invoice_service.create

        expect(result.invoice.issuing_date.to_s).to eq('2022-11-24')
      end
    end
  end
end
