# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::SubscriptionService, type: :service do
  subject(:invoice_service) do
    described_class.new(
      subscriptions:,
      timestamp: timestamp.to_i,
      invoicing_reason:
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, organization:, rate: 20) }

  let(:invoicing_reason) { :subscription_periodic }

  describe 'call' do
    let(:subscription) do
      create(
        :subscription,
        plan:,
        customer:,
        subscription_at: started_at.to_date,
        started_at:,
        created_at: started_at
      )
    end
    let(:subscriptions) { [subscription] }
    let(:lifetime_usage) { create(:lifetime_usage, subscription: subscription) }

    let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
    let(:timestamp) { Time.zone.now.beginning_of_month }
    let(:started_at) { Time.zone.now - 2.years }

    let(:plan) { create(:plan, interval: 'monthly', pay_in_advance:) }
    let(:pay_in_advance) { false }

    before do
      tax
      create(:standard_charge, plan: subscription.plan, charge_model: 'standard')
      lifetime_usage

      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::Payments::StripeCreateJob).to receive(:perform_later).and_call_original
      allow(Invoices::Payments::GocardlessCreateJob).to receive(:perform_later).and_call_original
      allow(Invoices::TransitionToFinalStatusService).to receive(:call).and_call_original
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

    it 'creates an invoice' do
      result = invoice_service.call

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice.invoice_subscriptions.first.to_datetime)
          .to match_datetime((timestamp - 1.day).end_of_day)
        expect(result.invoice.invoice_subscriptions.first.from_datetime)
          .to match_datetime((timestamp - 1.month).beginning_of_day)

        expect(result.invoice.subscriptions.first).to eq(subscription)
        expect(result.invoice.issuing_date.to_date).to eq(timestamp)
        expect(result.invoice.invoice_type).to eq('subscription')
        expect(result.invoice.payment_status).to eq('pending')
        expect(result.invoice.fees.subscription_kind.count).to eq(1)
        expect(result.invoice.fees.charge_kind.count).to eq(1)

        expect(result.invoice.currency).to eq('EUR')
        expect(result.invoice.fees_amount_cents).to eq(100)

        expect(result.invoice.taxes_amount_cents).to eq(20)
        expect(result.invoice.taxes_rate).to eq(20)
        expect(result.invoice.applied_taxes.count).to eq(1)

        expect(result.invoice.total_amount_cents).to eq(120)
        expect(result.invoice.version_number).to eq(4)
        expect(Invoices::TransitionToFinalStatusService).to have_received(:call).with(invoice: result.invoice)
        expect(result.invoice).to be_finalized
      end
    end

    it_behaves_like 'syncs invoice' do
      let(:service_call) { invoice_service.call }
    end

    it_behaves_like 'syncs sales order' do
      let(:service_call) { invoice_service.call }
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        invoice_service.call
      end.to have_enqueued_job(SendWebhookJob).with('invoice.created', Invoice)
    end

    it 'enqueues GeneratePdfAndNotifyJob with email false' do
      expect do
        invoice_service.call
      end.to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: false))
    end

    it 'flags lifetime usage for refresh' do
      create(:usage_threshold, plan:)

      invoice_service.call

      expect(subscription.reload.lifetime_usage.recalculate_invoiced_usage).to be(true)
    end

    context 'when there is tax provider integration' do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
      let(:response) { instance_double(Net::HTTPOK) }
      let(:lago_client) { instance_double(LagoHttpClient::Client) }
      let(:endpoint) { 'https://api.nango.dev/v1/anrok/finalized_invoices' }
      let(:body) do
        p = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/success_response_multiple_fees.json')
        json = File.read(p)

        # setting item_id based on the test example
        response = JSON.parse(json)
        response['succeededInvoices'].first['fees'].first['item_id'] = subscription.id
        response['succeededInvoices'].first['fees'].last['item_id'] = plan.charges.first.billable_metric.id

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
        integration_customer

        allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
        allow(lago_client).to receive(:post_with_response).and_return(response)
        allow(response).to receive(:body).and_return(body)
      end

      it 'creates an invoice' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.issuing_date.to_date).to eq(timestamp)
          expect(result.invoice.invoice_type).to eq('subscription')
          expect(result.invoice.payment_status).to eq('pending')
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)

          expect(result.invoice.currency).to eq('EUR')
          expect(result.invoice.fees_amount_cents).to eq(100)

          expect(result.invoice.taxes_amount_cents).to eq(10)
          expect(result.invoice.taxes_rate).to eq(10)
          expect(result.invoice.applied_taxes.count).to eq(2)

          expect(result.invoice.total_amount_cents).to eq(110)
          expect(result.invoice.version_number).to eq(4)
          expect(result.invoice).to be_finalized
        end
      end

      context 'when there is error received from the provider' do
        let(:body) do
          p = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json')
          File.read(p)
        end

        it 'returns tax error' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:tax_error]).to eq(['taxDateTooFarInFuture'])

            invoice = customer.invoices.order(created_at: :desc).first

            expect(invoice.status).to eq('failed')
            expect(invoice.error_details.count).to eq(1)
            expect(invoice.error_details.first.details['tax_error']).to eq('taxDateTooFarInFuture')
          end
        end
      end
    end

    context 'when periodic but no active subscriptions' do
      it 'does not create any invoices' do
        subscription.terminated!
        expect { invoice_service.call }.not_to change(Invoice, :count)
      end
    end

    context 'with lago_premium' do
      around { |test| lago_premium!(&test) }

      it 'enqueues GeneratePdfAndNotifyJob with email true' do
        expect do
          invoice_service.call
        end.to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: true))
      end

      context 'when organization does not have right email settings' do
        before { subscription.customer.organization.update!(email_settings: []) }

        it 'enqueues GeneratePdfAndNotifyJob with email false' do
          expect do
            invoice_service.call
          end.to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: false))
        end
      end
    end

    context 'with customer timezone' do
      before { subscription.customer.update!(timezone: 'America/Los_Angeles', invoice_grace_period: 3) }

      let(:timestamp) { DateTime.parse('2022-11-25 01:00:00') }

      it 'assigns the issuing date in the customer timezone' do
        result = invoice_service.call

        expect(result.invoice.issuing_date.to_s).to eq('2022-11-27')
      end
    end

    context 'with applicable grace period' do
      before do
        subscription.customer.update!(invoice_grace_period: 3)
      end

      it 'does not track any invoice creation on segment' do
        invoice_service.call
        expect(SegmentTrackJob).not_to have_received(:perform_later)
      end

      it 'does not create any payment' do
        invoice_service.call
        expect(Invoices::Payments::StripeCreateJob).not_to have_received(:perform_later)
        expect(Invoices::Payments::GocardlessCreateJob).not_to have_received(:perform_later)
      end

      it 'creates an invoice as draft' do
        result = invoice_service.call
        expect(result).to be_success
        expect(result.invoice).to be_draft
      end

      it 'enqueues a SendWebhookJob' do
        expect do
          invoice_service.call
        end.to have_enqueued_job(SendWebhookJob).with('invoice.drafted', Invoice)
      end

      it 'does not flag lifetime usage for refresh' do
        invoice_service.call

        expect(lifetime_usage.reload.recalculate_invoiced_usage).to be(false)
      end
    end

    context 'when invoice already exists' do
      let(:timestamp) { Time.zone.parse('2023-10-01T00:00:00.000Z') }

      let(:invoice_subscription) do
        create(
          :invoice_subscription,
          invoice: old_invoice,
          subscription:,
          from_datetime: Time.zone.parse('2023-09-01T00:00:00.000Z'),
          to_datetime: Time.zone.parse('2023-09-30T23:59:59.999Z').end_of_day,
          charges_from_datetime: Time.zone.parse('2023-09-01T00:00:00.000Z'),
          charges_to_datetime: Time.zone.parse('2023-09-30T23:59:59.999Z').end_of_day,
          recurring: invoicing_reason.to_sym == :subscription_periodic,
          invoicing_reason:
        )
      end

      let(:old_invoice) do
        create(
          :invoice,
          created_at: timestamp + 1.second,
          customer: subscription.customer,
          organization: plan.organization
        )
      end

      before { invoice_subscription }

      it 'does not raise an error' do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice).to be_nil
      end
    end

    context 'when skip zero invoices is set' do
      before do
        customer.update(finalize_zero_amount_invoice: :skip)
      end

      context 'when invoice total amount is not 0' do
        it 'creates an invoice in :finalized status' do
          result = invoice_service.call
          expect(result.invoice.status).to eq('finalized')
          expect(result.invoice.number).not_to include('DRAFT')
        end
      end

      context 'when invoice total amount is 0' do
        let(:plan) { create(:plan, interval: 'monthly', pay_in_advance:, amount_cents: 0) }

        before do
          plan
        end

        it 'creates an invoice in :closed status' do
          result = invoice_service.call
          expect(result.invoice.status).to eq('closed')
          expect(result.invoice.number).to include('DRAFT')
        end

        context 'when organization gas grace period' do
          before do
            organization.update!(invoice_grace_period: 30)
          end

          it 'creates an invoice in :draft status' do
            result = invoice_service.call
            expect(result.invoice.status).to eq('draft')
          end
        end
      end
    end
  end
end
