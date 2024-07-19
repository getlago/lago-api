# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::RetryService, type: :service do
  subject(:retry_service) { described_class.new(invoice:) }

  describe '#call' do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }

    let(:invoice) do
      create(
        :invoice,
        :failed,
        customer:,
        organization:,
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
    let(:plan) { create(:plan, organization:, interval: 'monthly') }
    let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
    let(:charge) { create(:standard_charge, plan: subscription.plan, charge_model: 'standard', billable_metric:) }

    let(:fee_subscription) do
      create(
        :fee,
        invoice:,
        subscription:,
        fee_type: :subscription,
        amount_cents: 2_000
      )
    end
    let(:fee_charge) do
      create(
        :fee,
        invoice:,
        charge:,
        fee_type: :charge,
        total_aggregated_units: 100,
        amount_cents: 1_000
      )
    end

    let(:integration) { create(:anrok_integration, organization:) }
    let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
    let(:response) { instance_double(Net::HTTPOK) }
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:endpoint) { 'https://api.nango.dev/v1/anrok/finalized_invoices' }
    let(:body) do
      path = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/success_response_multiple_fees.json')
      json = File.read(path)

      # setting item_id based on the test example
      response = JSON.parse(json)
      response['succeededInvoices'].first['fees'].first['item_id'] = subscription.id
      response['succeededInvoices'].first['fees'].last['item_id'] = billable_metric.id

      response.to_json
    end
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
      fee_subscription
      fee_charge

      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::Payments::StripeCreateJob).to receive(:perform_later).and_call_original
      allow(Invoices::Payments::GocardlessCreateJob).to receive(:perform_later).and_call_original

      integration_customer

      allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
      allow(lago_client).to receive(:post_with_response).and_return(response)
      allow(response).to receive(:body).and_return(body)
    end

    context 'when invoice does not exist' do
      it 'returns an error' do
        result = described_class.new(invoice: nil).call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('invoice_not_found')
      end
    end

    context 'when invoice is in draft status' do
      before do
        invoice.update(status: :draft)
      end

      it 'returns an error' do
        result = retry_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq('invalid_status')
      end
    end

    it 'marks the invoice as finalized' do
      expect { retry_service.call }
        .to change(invoice, :status).from('failed').to('finalized')
    end

    it 'updates the issuing date and payment due date' do
      invoice.customer.update(timezone: 'America/New_York')

      freeze_time do
        current_date = Time.current.in_time_zone('America/New_York').to_date

        expect { retry_service.call }
          .to change { invoice.reload.issuing_date }.to(current_date)
          .and change { invoice.reload.payment_due_date }.to(current_date)
      end
    end

    it 'generates invoice number' do
      customer_slug = "#{organization.document_number_prefix}-#{format("%03d", customer.sequential_id)}"
      sequential_id = customer.invoices.where.not(id: invoice.id).order(created_at: :desc).first&.sequential_id || 0

      expect { retry_service.call }
        .to change { invoice.reload.number }
        .from("#{organization.document_number_prefix}-DRAFT")
        .to("#{customer_slug}-#{format("%03d", sequential_id + 1)}")
    end

    it 'generates expected invoice totals' do
      result = retry_service.call

      aggregate_failures do
        expect(result).to be_success
        expect(result.invoice.fees.charge_kind.count).to eq(1)
        expect(result.invoice.fees.subscription_kind.count).to eq(1)

        expect(result.invoice.currency).to eq('EUR')
        expect(result.invoice.fees_amount_cents).to eq(3_000)

        expect(result.invoice.taxes_amount_cents).to eq(350)
        expect(result.invoice.taxes_rate.round(2)).to eq(11.67) # (0.667 * 10) + (0.333 * 15)
        expect(result.invoice.applied_taxes.count).to eq(2)

        expect(result.invoice.total_amount_cents).to eq(3_350)
      end
    end

    it_behaves_like 'syncs invoice' do
      let(:service_call) { retry_service.call }
    end

    it_behaves_like 'syncs sales order' do
      let(:service_call) { retry_service.call }
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        retry_service.call
      end.to have_enqueued_job(SendWebhookJob).with('invoice.created', Invoice)
    end

    it 'enqueues GeneratePdfAndNotifyJob with email false' do
      expect do
        retry_service.call
      end.to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: false))
    end

    context 'with lago_premium' do
      around { |test| lago_premium!(&test) }

      it 'enqueues GeneratePdfAndNotifyJob with email true' do
        expect do
          retry_service.call
        end.to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: true))
      end

      context 'when organization does not have right email settings' do
        before { invoice.organization.update!(email_settings: []) }

        it 'enqueues GeneratePdfAndNotifyJob with email false' do
          expect do
            retry_service.call
          end.to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: false))
        end
      end
    end

    it 'calls SegmentTrackJob' do
      invoice = retry_service.call.invoice

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

      retry_service.call
      expect(Invoices::Payments::CreateService).to have_received(:new)
      expect(payment_create_service).to have_received(:call)
    end

    context 'when organization does not have a webhook endpoint' do
      before { invoice.organization.webhook_endpoints.destroy_all }

      it 'does not enqueue a SendWebhookJob' do
        expect do
          retry_service.call
        end.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'with credit notes' do
      let(:credit_note) do
        create(
          :credit_note,
          customer:,
          total_amount_cents: 10,
          total_amount_currency: 'EUR',
          balance_amount_cents: 10,
          balance_amount_currency: 'EUR',
          credit_amount_cents: 10,
          credit_amount_currency: 'EUR'
        )
      end

      before { credit_note }

      it 'updates the invoice accordingly' do
        result = retry_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.fees_amount_cents).to eq(3_000)
          expect(result.invoice.taxes_amount_cents).to eq(350)
          expect(result.invoice.total_amount_cents).to eq(3_340)
          expect(result.invoice.credits.count).to eq(1)

          credit = result.invoice.credits.first
          expect(credit.credit_note).to eq(credit_note)
          expect(credit.amount_cents).to eq(10)
        end
      end
    end
  end
end
