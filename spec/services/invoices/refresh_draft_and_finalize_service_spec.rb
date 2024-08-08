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

    it 'enqueues GeneratePdfAndNotifyJob with email false' do
      expect do
        finalize_service.call
      end.to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: false))
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
      payment_create_service = instance_double(Invoices::Payments::CreateService)
      allow(Invoices::Payments::CreateService).to receive(:new).and_return(payment_create_service)
      allow(payment_create_service).to receive(:call)

      finalize_service.call
      expect(Invoices::Payments::CreateService).to have_received(:new)
      expect(payment_create_service).to have_received(:call)
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

    context 'when tax integration is set up' do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
      let(:response) { instance_double(Net::HTTPOK) }
      let(:lago_client) { instance_double(LagoHttpClient::Client) }
      let(:endpoint) { 'https://api.nango.dev/v1/anrok/finalized_invoices' }
      let(:integration_collection_mapping) do
        create(
          :netsuite_collection_mapping,
          integration:,
          mapping_type: :fallback_item,
          settings: {external_id: '1', external_account_code: '11', external_name: ''}
        )
      end

      before do
        integration_collection_mapping
        integration_customer
        invoice.update(issuing_date: Time.current + 3.months)

        allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
        allow(lago_client).to receive(:post_with_response).and_return(response)
        allow(response).to receive(:body).and_return(body)
        allow(Invoices::ApplyProviderTaxesService).to receive(:call).and_call_original
        allow(SendWebhookJob).to receive(:perform_later).and_call_original
        allow(Invoices::GeneratePdfAndNotifyJob).to receive(:perform_later).and_call_original
        allow(Integrations::Aggregator::Invoices::CreateJob).to receive(:perform_later).and_call_original
        allow(Integrations::Aggregator::SalesOrders::CreateJob).to receive(:perform_later).and_call_original
        allow(Invoices::Payments::CreateService).to receive(:new).and_call_original
        allow(Utils::SegmentTrack).to receive(:invoice_created).and_call_original
      end

      context 'when taxes fetched correctly' do
        let(:body) do
          p = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/success_response_multiple_fees.json')
          json = File.read(p)

          response = JSON.parse(json)
          response['succeededInvoices'].first['fees'].first['item_id'] = subscription.id
          response['succeededInvoices'].first['fees'].last['item_id'] = plan.billable_metrics.first.id

          response.to_json
        end
        let(:invoice_issuing_date) { Time.current.in_time_zone(invoice.customer.applicable_timezone).to_date }

        it 'refreshes all data and applies fetched taxes' do
          aggregate_failures do
            expect { finalize_service.call }.to change { invoice.reload.taxes_rate }.from(0.0).to(10.0)
              .and change { invoice.fees.count }.from(0).to(2)
            expect(LagoHttpClient::Client).to have_received(:new).with(endpoint)
            expect(Invoices::ApplyProviderTaxesService).to have_received(:call)
          end
        end

        it 'finalizes the invoice' do
          expect { finalize_service.call }.to change { invoice.reload.status }.from('draft').to('finalized')
        end

        it 'sends finalized invoice issuing date to tax_provider' do
          finalize_service.call
          expect(lago_client).to have_received(:post_with_response)
            .with([hash_including('issuing_date' => invoice_issuing_date)], anything)
        end
      end

      context 'when fetched taxes with errors' do
        let(:body) do
          p = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json')
          File.read(p)
        end

        it 'returns error' do
          result = finalize_service.call
          aggregate_failures do
            expect(invoice.reload.status).to eql('failed')
            expect(result.success?).to be(false)
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:tax_error]).to eq(['taxDateTooFarInFuture'])
          end
        end

        it 'moves invoice to failed state' do
          expect { finalize_service.call }.to change(invoice.reload, :status).from('draft').to('failed')
        end

        it 'creates a new error_detail for the invoice' do
          expect { finalize_service.call }.to change(invoice.error_details, :count).from(0).to(1)
        end

        it 'updates fees despite error result' do
          expect { finalize_service.call }.to change(invoice.fees.charge_kind, :count).from(0).to(1)
            .and change(invoice.fees.subscription_kind, :count).from(0).to(1)
        end

        it 'does not send any updates' do
          finalize_service.call
          aggregate_failures do
            expect(SendWebhookJob).not_to have_received(:perform_later)
            expect(Invoices::GeneratePdfAndNotifyJob).not_to have_received(:perform_later)
            expect(Integrations::Aggregator::Invoices::CreateJob).not_to have_received(:perform_later)
            expect(Integrations::Aggregator::SalesOrders::CreateJob).not_to have_received(:perform_later)
            expect(Invoices::Payments::CreateService).not_to have_received(:new)
            expect(Utils::SegmentTrack).not_to have_received(:invoice_created)
          end
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
  end
end
