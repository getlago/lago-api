# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::FinalizeService, type: :service do
  subject(:finalize_service) { described_class.new(invoice:) }

  describe '#call' do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }

    let(:invoice) do
      create(
        :invoice,
        :draft,
        customer:,
        subscriptions: [subscription],
        currency: 'EUR',
        issuing_date: Time.zone.at(timestamp).to_date
      )
    end

    let(:subscription) do
      create(
        :subscription,
        plan:,
        subscription_at: started_at,
        started_at:,
        created_at: started_at
      )
    end

    let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
    let(:timestamp) { Time.zone.now - 1.year }
    let(:started_at) { Time.zone.now - 2.years }
    let(:fee) { create(:fee, invoice:, subscription:) }
    let(:plan) { create(:plan, organization:, interval: 'monthly') }
    let(:credit_note) { create(:credit_note, :draft, invoice:) }

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
        current_date = Time.current.in_time_zone('America/New_York').to_date

        expect { finalize_service.call }
          .to change { invoice.reload.issuing_date }.to(current_date)
          .and change { invoice.reload.payment_due_date }.to(current_date)
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

    it_behaves_like 'syncs invoice' do
      let(:service_call) { finalize_service.call }
    end

    it_behaves_like 'syncs sales order' do
      let(:service_call) { finalize_service.call }
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        finalize_service.call
      end.to have_enqueued_job(SendWebhookJob).with('invoice.created', Invoice)
    end

    it 'does not enqueue an SendEmailJob' do
      expect do
        finalize_service.call
      end.not_to have_enqueued_job(SendEmailJob)
    end

    context 'with lago_premium' do
      around { |test| lago_premium!(&test) }

      it 'enqueues an SendEmailJob' do
        expect do
          finalize_service.call
        end.to have_enqueued_job(SendEmailJob)
      end

      context 'when organization does not have right email settings' do
        before { invoice.organization.update!(email_settings: []) }

        it 'does not enqueue an SendEmailJob' do
          expect do
            finalize_service.call
          end.not_to have_enqueued_job(SendEmailJob)
        end
      end
    end

    it 'calls SegmentTrackJob' do
      invoice = finalize_service.call.invoice

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
      allow(Invoices::Payments::CreateService).to receive(:new).and_return(payment_create_service)
      allow(payment_create_service).to receive(:call)

      finalize_service.call
      expect(Invoices::Payments::CreateService).to have_received(:new)
      expect(payment_create_service).to have_received(:call)
    end

    context 'when organization does not have a webhook endpoint' do
      before { invoice.organization.webhook_endpoints.destroy_all }

      it 'does not enqueue a SendWebhookJob' do
        expect do
          finalize_service.call
        end.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when invoice does not exist' do
      it 'returns an error' do
        result = described_class.new(invoice: nil).call
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

    context 'with credit notes' do
      before do
        create(:credit_note_item, credit_note:, fee:)
      end

      it 'marks the credit notes as finalized' do
        expect { finalize_service.call }
          .to change { credit_note.reload.status }.from('draft').to('finalized')
      end

      it 'calls SegmentTrackJob' do
        invoice = finalize_service.call.invoice
        credit_note = invoice.credit_notes.first

        expect(SegmentTrackJob).to have_received(:perform_later).with(
          membership_id: CurrentContext.membership,
          event: 'credit_note_issued',
          properties: {
            organization_id: credit_note.organization.id,
            credit_note_id: credit_note.id,
            invoice_id: credit_note.invoice_id,
            credit_note_method: 'credit'
          }
        )
      end

      it 'enqueues a SendWebhookJob' do
        expect do
          finalize_service.call
        end.to have_enqueued_job(SendWebhookJob).with('credit_note.created', CreditNote)
      end
    end
  end
end
