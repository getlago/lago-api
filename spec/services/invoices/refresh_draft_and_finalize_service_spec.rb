# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::RefreshDraftAndFinalizeService, type: :service do
  subject(:finalize_service) { described_class.new(invoice:) }

  describe '#call' do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }

    let(:invoice) do
      create(
        :invoice,
        :draft,
        organization:,
        customer:,
        subscriptions: [subscription],
        currency: 'EUR',
        issuing_date: Time.zone.at(timestamp).to_date
      )
    end

    let(:subscription) do
      create(
        :subscription,
        customer:,
        plan:,
        subscription_at: started_at,
        started_at:,
        created_at: started_at
      )
    end

    let(:timestamp) { Time.zone.now - 1.year }
    let(:started_at) { Time.zone.now - 2.years }
    let(:fee) { create(:fee, invoice:, subscription:) }
    let(:plan) { create(:plan, organization:, interval: 'monthly') }
    let(:credit_note) { create(:credit_note, :draft, invoice:) }
    let(:standard_charge) { create(:standard_charge, plan: subscription.plan, charge_model: 'standard') }

    before do
      standard_charge

      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::Payments::CreateService).to receive(:call_async).and_call_original
      allow(Invoices::TransitionToFinalStatusService).to receive(:call).and_call_original
    end

    it 'marks the invoice as finalized' do
      expect { finalize_service.call }
        .to change(invoice, :status).from('draft').to('finalized')
      expect(Invoices::TransitionToFinalStatusService).to have_received(:call).with(invoice:)
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
        expect(result.invoice.fees.charge.count).to eq(1)
        expect(result.invoice.fees.subscription.count).to eq(1)
      end
    end

    it_behaves_like 'syncs invoice' do
      let(:service_call) { finalize_service.call }
    end

    it_behaves_like "applies invoice_custom_sections" do
      let(:service_call) { finalize_service.call }
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        finalize_service.call
      end.to have_enqueued_job(SendWebhookJob).with('invoice.created', Invoice)
    end

    it 'enqueues GeneratePdfAndNotifyJob with email false' do
      expect do
        finalize_service.call
      end.to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: false))
    end

    it 'flags lifetime usage for refresh' do
      create(:usage_threshold, plan:)

      finalize_service.call

      expect(subscription.reload.lifetime_usage.recalculate_invoiced_usage).to be(true)
    end

    context 'with lago_premium' do
      around { |test| lago_premium!(&test) }

      it 'enqueues GeneratePdfAndNotifyJob with email true' do
        expect do
          finalize_service.call
        end.to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: true))
      end

      context 'when organization does not have right email settings' do
        before { invoice.organization.update!(email_settings: []) }

        it 'enqueues GeneratePdfAndNotifyJob with email false' do
          expect do
            finalize_service.call
          end.to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: false))
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
      allow(Invoices::Payments::CreateService).to receive(:call_async)

      finalize_service.call
      expect(Invoices::Payments::CreateService).to have_received(:call_async)
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
          expect(result.invoice.fees.charge.count).to eq(1)
          expect(result.invoice.fees.subscription.count).to eq(1)
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

      it 'enqueues CreditNotes::GeneratePdfJob' do
        expect do
          finalize_service.call
        end.to have_enqueued_job(CreditNotes::GeneratePdfJob)
      end
    end

    context 'when tax integration is set up' do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:) }

      before do
        integration_customer
        invoice.update(issuing_date: Time.current + 3.months)

        allow(Invoices::ApplyProviderTaxesService).to receive(:call).and_call_original
        allow(SendWebhookJob).to receive(:perform_later).and_call_original
        allow(Invoices::GeneratePdfAndNotifyJob).to receive(:perform_later).and_call_original
        allow(Integrations::Aggregator::Invoices::CreateJob).to receive(:perform_later).and_call_original
        allow(Invoices::Payments::CreateService).to receive(:new).and_call_original
        allow(Utils::SegmentTrack).to receive(:invoice_created).and_call_original
      end

      context 'when taxes are unknown' do
        it 'returns pending invoice' do
          result = finalize_service.call
          aggregate_failures do
            expect(invoice.reload.status).to eql('pending')
            expect(result.success?).to be(true)
          end
        end

        it 'moves invoice to pending tax state' do
          expect { finalize_service.call }.to change(invoice.reload, :tax_status).from(nil).to('pending')
        end

        it 'updates fees despite error result' do
          expect { finalize_service.call }.to change(invoice.fees.charge, :count).from(0).to(1)
            .and change(invoice.fees.subscription, :count).from(0).to(1)
        end

        it 'does not send any updates' do
          finalize_service.call
          aggregate_failures do
            expect(SendWebhookJob).not_to have_received(:perform_later).with('invoice.created', invoice)
            expect(Invoices::GeneratePdfAndNotifyJob).not_to have_received(:perform_later)
            expect(Integrations::Aggregator::Invoices::CreateJob).not_to have_received(:perform_later)
            expect(Invoices::Payments::CreateService).not_to have_received(:new)
            expect(Utils::SegmentTrack).not_to have_received(:invoice_created)
          end
        end

        it 'does not change issuing_date on the invoice' do
          expect { finalize_service.call }.not_to change(invoice, :issuing_date)
        end
      end
    end

    context 'when sending an invoice that is not draft' do
      let(:invoice) do
        create(
          :invoice,
          :failed,
          customer:,
          subscriptions: [subscription],
          currency: 'EUR',
          issuing_date: Time.zone.at(timestamp).to_date
        )
      end

      it 'does not update the invoice' do
        expect { finalize_service.call }.not_to change { invoice.reload.status }
      end
    end

    context 'when invoice has invoice_errors' do
      before do
        InvoiceError.create(
          id: invoice.id,
          backtrace: "[\"/app/app/models/invoice.rb:432:in 'generate_organization_sequential_id'\", \"/app/app/models/invoice.rb:395:in...",
          error: "\"#\\u003cSequenced::SequenceError: Unable to acquire lock on the database\\u003e\"",
          invoice: invoice.to_json(except: :file),
          subscriptions: invoice.subscriptions.to_json
        )
      end

      context 'when successfully generated the invoice' do
        it 'deletes the invoice_errors' do
          expect { finalize_service.call }.to change(InvoiceError, :count).by(-1)
          expect(InvoiceError.find_by(id: invoice.id)).to be_nil
        end
      end

      context 'when failed to generate the invoice' do
        before do
          allow(Invoices::RefreshDraftService).to receive(:call).and_return(BaseService::Result.new.service_failure!(code: 'code', message: 'message'))
        end

        it 'does not delete the invoice_errors' do
          expect { finalize_service.call }.to raise_error(BaseService::ServiceFailure)
          expect(InvoiceError.find_by(id: invoice.id)).to be_present
        end
      end
    end
  end
end
