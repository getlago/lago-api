# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::FinalizeOpenCreditService, type: :service do
  let(:service) { described_class.new(invoice:) }

  let(:organization) { create(:organization, email_settings: Organization::EMAIL_SETTINGS) }
  let(:invoice) { create(:invoice, organization:, invoice_type: 'credit', status: :open, payment_due_date: 1.week.ago.to_date) }

  before do
    allow(invoice).to receive(:should_sync_invoice?).and_return(true)
    allow(invoice).to receive(:should_sync_sales_order?).and_return(true)
  end

  describe '.call' do
    around { |test| lago_premium!(&test) }

    it 'updates invoice status and enqueues necessary jobs' do
      result = service.call

      expect(result.invoice.status).to eq('finalized')
      expect(result.invoice.issuing_date).to be_today
      expect(result.invoice.payment_due_date).to be_today

      expect(SendWebhookJob).to have_been_enqueued.with('invoice.paid_credit_added', result.invoice)
      expect(Invoices::GeneratePdfAndNotifyJob).to have_been_enqueued.with(invoice: result.invoice, email: true)
      expect(Integrations::Aggregator::Invoices::CreateJob).to have_been_enqueued.with(invoice: result.invoice)
      expect(Integrations::Aggregator::SalesOrders::CreateJob).to have_been_enqueued.with(invoice: result.invoice)
      expect(SegmentTrackJob).to have_been_enqueued.with(membership_id: anything, event: 'invoice_created', properties: {
        organization_id: result.invoice.organization.id,
        invoice_id: result.invoice.id,
        invoice_type: result.invoice.invoice_type
      })
    end

    context 'when invoice is already finalized' do
      let(:invoice) { create(:invoice, organization:, invoice_type: 'credit', status: :finalized) }

      it 'does not update invoice status' do
        result = service.call

        expect(result.invoice.status).to eq('finalized')

        expect(SendWebhookJob).not_to have_been_enqueued
        expect(Invoices::GeneratePdfAndNotifyJob).not_to have_been_enqueued
        expect(Integrations::Aggregator::Invoices::CreateJob).not_to have_been_enqueued
        expect(Integrations::Aggregator::SalesOrders::CreateJob).not_to have_been_enqueued
        expect(SegmentTrackJob).not_to have_been_enqueued
      end
    end

    context 'when invoice is not found' do
      let(:invoice) { nil }

      it 'returns not found failure' do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('invoice_not_found')
      end
    end
  end
end
