# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::FinalizeService, type: :service do
  subject(:finalize_service) { described_class.new(invoice:) }

  describe '#call' do
    let(:invoice) do
      create(
        :invoice,
        :draft,
        subscriptions: [subscription],
        amount_currency: 'EUR',
        vat_amount_currency: 'EUR',
        total_amount_currency: 'EUR',
        issuing_date: Time.zone.at(timestamp).to_date,
      )
    end

    let(:subscription) do
      create(
        :subscription,
        plan:,
        subscription_at: started_at,
        started_at:,
        created_at: started_at,
      )
    end

    let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
    let(:timestamp) { Time.zone.now.beginning_of_month }
    let(:started_at) { Time.zone.now - 2.years }
    let(:credit_note) { create(:credit_note, :draft, invoice:) }

    let(:plan) { create(:plan, interval: 'monthly') }

    before do
      create(:standard_charge, plan: subscription.plan, charge_model: 'standard')

      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::Payments::StripeCreateJob).to receive(:perform_later).and_call_original
      allow(Invoices::Payments::GocardlessCreateJob).to receive(:perform_later).and_call_original
    end

    it 'marks the invoice as finalized' do
      expect { finalize_service.call }
        .to change(invoice, :status).from('draft').to('finalized')
    end

    it 'updates the issuing date' do
      invoice.customer.update(timezone: 'America/New_York')

      freeze_time do
        expect { finalize_service.call }
          .to change { invoice.reload.issuing_date }.to(Time.current.to_date)
      end
    end

    it 'generates expected fees' do
      result = finalize_service.call

      aggregate_failures do
        expect(result).to be_success
        expect(result.invoice.fees.charge_kind.count).to eq(1)
        expect(result.invoice.fees.subscription_kind.count).to eq(1)
      end
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        finalize_service.call
      end.to have_enqueued_job(SendWebhookJob).with(:invoice, Invoice)
    end

    it 'calls SegmentTrackJob' do
      invoice = finalize_service.call.invoice

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
      allow(Invoices::Payments::CreateService).to receive(:new).and_return(payment_create_service)
      allow(payment_create_service).to receive(:call)

      finalize_service.call
      expect(Invoices::Payments::CreateService).to have_received(:new)
      expect(payment_create_service).to have_received(:call)
    end

    context 'when organization does not have a webhook url' do
      before { invoice.organization.update!(webhook_url: nil) }

      it 'does not enqueue a SendWebhookJob' do
        expect do
          finalize_service.call
        end.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when invoice does not exist' do
      let(:invoice) { nil }

      it 'returns an error' do
        result = finalize_service.call
        expect(result).not_to be_success
        expect(result.error.error_code).to eq('invoice_not_found')
      end
    end

    context 'when fees already exist' do
      it 'regenerates them' do
        create(:fee, invoice:)
        result = finalize_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.fees.charge_kind.count).to eq(1)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
        end
      end
    end
  end
end
