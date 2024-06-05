# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::PaidCreditService, type: :service do
  subject(:invoice_service) do
    described_class.new(wallet_transaction:, timestamp:, invoice:)
  end

  let(:timestamp) { Time.current.to_i }

  describe 'call' do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, plan:, customer:) }
    let(:plan) { create(:plan, organization:) }
    let(:wallet) { create(:wallet, customer:) }
    let(:wallet_transaction) do
      create(:wallet_transaction, wallet:, amount: '15.00', credit_amount: '15.00')
    end

    let(:invoice) { nil }

    before do
      wallet_transaction
      subscription
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates an invoice' do
      result = invoice_service.call

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice).to have_attributes(
          issuing_date: Time.zone.at(timestamp).to_date,
          invoice_type: 'credit',
          payment_status: 'pending',
          currency: 'EUR',
          fees_amount_cents: 1500,
          sub_total_excluding_taxes_amount_cents: 1500,
          taxes_amount_cents: 0,
          taxes_rate: 0,
          sub_total_including_taxes_amount_cents: 1500,
          total_amount_cents: 1500
        )

        expect(result.invoice.applied_taxes.count).to eq(0)

        expect(result.invoice).to be_finalized
      end
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        invoice_service.call
      end.to have_enqueued_job(SendWebhookJob)
    end

    it_behaves_like 'syncs invoice' do
      let(:service_call) { invoice_service.call }
    end

    it_behaves_like 'syncs sales order' do
      let(:service_call) { invoice_service.call }
    end

    it 'does not enqueue an SendEmailJob' do
      expect do
        invoice_service.call
      end.not_to have_enqueued_job(SendEmailJob)
    end

    context 'with lago_premium' do
      around { |test| lago_premium!(&test) }

      it 'enqueues an SendEmailJob' do
        expect do
          invoice_service.call
        end.to have_enqueued_job(SendEmailJob)
      end

      context 'when organization does not have right email settings' do
        before { customer.organization.update!(email_settings: []) }

        it 'does not enqueue an SendEmailJob' do
          expect do
            invoice_service.call
          end.not_to have_enqueued_job(SendEmailJob)
        end
      end
    end

    it 'calls SegmentTrackJob' do
      invoice = invoice_service.call.invoice

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

    it 'creates a payment' do
      payment_create_service = instance_double(Invoices::Payments::CreateService)
      allow(Invoices::Payments::CreateService)
        .to receive(:new).and_return(payment_create_service)
      allow(payment_create_service)
        .to receive(:call)

      invoice_service.call

      expect(Invoices::Payments::CreateService).to have_received(:new)
      expect(payment_create_service).to have_received(:call)
    end

    context 'when organization does not have a webhook endpoint' do
      before { customer.organization.webhook_endpoints.destroy_all }

      it 'does not enqueues a SendWebhookJob' do
        expect do
          invoice_service.call
        end.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'with customer timezone' do
      before { customer.update!(timezone: 'America/Los_Angeles') }

      let(:timestamp) { DateTime.parse('2022-11-25 01:00:00').to_i }

      it 'assigns the issuing date in the customer timezone' do
        result = invoice_service.call

        expect(result.invoice.issuing_date.to_s).to eq('2022-11-24')
      end
    end

    context 'with provided invoice' do
      let(:invoice) do
        create(:invoice, organization: customer.organization, customer:, invoice_type: :credit, status: :generating)
      end

      it 'does not re-create an invoice' do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)

        expect(result.invoice.fees.count).to eq(1)

        expect(result.invoice.fees_amount_cents).to eq(1500)
        expect(result.invoice.taxes_amount_cents).to eq(0)
        expect(result.invoice.taxes_rate).to eq(0)
        expect(result.invoice.total_amount_cents).to eq(1500)

        expect(result.invoice).to be_finalized
      end
    end
  end
end
