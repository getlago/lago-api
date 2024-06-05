# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::CreatePayInAdvanceChargeService, type: :service do
  subject(:invoice_service) do
    described_class.new(charge:, event:, timestamp: timestamp.to_i, invoice:)
  end

  let(:timestamp) { Time.zone.now.beginning_of_month }
  let(:organization) { create(:organization, email_settings:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:charge) { create(:standard_charge, :pay_in_advance, billable_metric:, plan:) }
  let(:charge_filter) { nil }

  let(:invoice) { nil }

  let(:email_settings) { ['invoice.finalized', 'credit_note.created'] }

  let(:event) do
    create(
      :event,
      external_subscription_id: subscription.external_id,
      external_customer_id: customer.external_id,
      organization_id: organization.id
    )
  end

  before { create(:tax, organization:, applied_to_organization: true) }

  describe 'call' do
    let(:aggregation_result) do
      BaseService::Result.new.tap do |result|
        result.aggregation = 9
        result.count = 4
        result.options = {}
      end
    end

    let(:charge_result) do
      BaseService::Result.new.tap do |result|
        result.amount = 10
        result.unit_amount = 0.01111111111
        result.count = 1
        result.units = 9
      end
    end

    before do
      allow(Charges::PayInAdvanceAggregationService).to receive(:call)
        .with(charge:, boundaries: Hash, properties: Hash, event:, charge_filter:)
        .and_return(aggregation_result)

      allow(Charges::ApplyPayInAdvanceChargeModelService).to receive(:call)
        .with(charge:, aggregation_result:, properties: Hash)
        .and_return(charge_result)

      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates an invoice' do
      result = invoice_service.call

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice.issuing_date.to_date).to eq(timestamp)
        expect(result.invoice.payment_due_date.to_date).to eq(timestamp)
        expect(result.invoice.organization_id).to eq(organization.id)
        expect(result.invoice.customer_id).to eq(customer.id)
        expect(result.invoice.invoice_type).to eq('subscription')
        expect(result.invoice.payment_status).to eq('pending')

        expect(result.invoice.fees.where(fee_type: :charge).count).to eq(1)
        expect(result.invoice.fees.first).to have_attributes(
          subscription:,
          charge:,
          amount_cents: 10,
          amount_currency: 'EUR',
          taxes_rate: 20.0,
          taxes_amount_cents: 2,
          fee_type: 'charge',
          pay_in_advance: true,
          invoiceable: charge,
          units: 9,
          properties: Hash,
          events_count: 1,
          charge_filter: nil,
          pay_in_advance_event_id: event.id,
          payment_status: 'pending',
          unit_amount_cents: 1,
          precise_unit_amount: 0.01111111111
        )

        expect(result.invoice.currency).to eq(customer.currency)
        expect(result.invoice.fees_amount_cents).to eq(10)

        expect(result.invoice.taxes_amount_cents).to eq(2)
        expect(result.invoice.taxes_rate).to eq(20)
        expect(result.invoice.applied_taxes.count).to eq(1)

        expect(result.invoice.total_amount_cents).to eq(12)

        expect(result.invoice).to be_finalized
      end
    end

    it 'creates InvoiceSubscription object' do
      expect { invoice_service.call.invoice }.to change(InvoiceSubscription, :count).by(1)
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

    it 'enqueues a SendWebhookJob for the invoice' do
      expect do
        invoice_service.call
      end.to have_enqueued_job(SendWebhookJob).with('invoice.created', Invoice)
    end

    it 'enqueues a SendWebhookJob for the fees' do
      expect do
        invoice_service.call
      end.to have_enqueued_job(SendWebhookJob).with('fee.created', Fee)
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
        let(:email_settings) { [] }

        it 'does not enqueue an SendEmailJob' do
          expect do
            invoice_service.call
          end.not_to have_enqueued_job(SendEmailJob)
        end
      end
    end

    context 'when organization does not have a webhook endpoint' do
      before { organization.webhook_endpoints.destroy_all }

      it 'does not enqueues a SendWebhookJob' do
        expect do
          invoice_service.call
        end.not_to have_enqueued_job(SendWebhookJob).with('invoice.created', Invoice)
      end
    end

    context 'with customer timezone' do
      let(:customer) { create(:customer, organization:, timezone: 'America/Los_Angeles') }
      let(:timestamp) { DateTime.parse('2022-11-25 01:00:00') }

      it 'assigns the issuing date in the customer timezone' do
        result = invoice_service.call

        expect(result.invoice.issuing_date.to_s).to eq('2022-11-24')
        expect(result.invoice.payment_due_date.to_s).to eq('2022-11-24')
      end
    end

    context 'with grace period' do
      let(:customer) { create(:customer, organization:, invoice_grace_period: 3) }
      let(:timestamp) { DateTime.parse('2022-11-25 08:00:00') }

      it 'assigns the correct issuing date' do
        result = invoice_service.call

        expect(result.invoice.issuing_date.to_s).to eq('2022-11-25')
      end
    end

    context 'with provided invoice' do
      let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :subscription, status: :generating) }

      it_behaves_like 'syncs invoice' do
        let(:service_call) { invoice_service.call }
      end

      it_behaves_like 'syncs sales order' do
        let(:service_call) { invoice_service.call }
      end

      it 'does not re-create an invoice' do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)

        expect(result.invoice.fees.where(fee_type: :charge).count).to eq(1)
        expect(result.invoice.fees.first).to have_attributes(
          subscription:,
          charge:,
          amount_cents: 10,
          amount_currency: 'EUR',
          taxes_rate: 20.0,
          taxes_amount_cents: 2,
          fee_type: 'charge',
          pay_in_advance: true,
          invoiceable: charge,
          units: 9,
          properties: Hash,
          events_count: 1,
          charge_filter: nil,
          pay_in_advance_event_id: event.id,
          payment_status: 'pending',
          unit_amount_cents: 1,
          precise_unit_amount: 0.01111111111
        )

        expect(result.invoice.currency).to eq(customer.currency)
        expect(result.invoice.fees_amount_cents).to eq(10)

        expect(result.invoice.taxes_amount_cents).to eq(2)
        expect(result.invoice.taxes_rate).to eq(20)
        expect(result.invoice.applied_taxes.count).to eq(1)

        expect(result.invoice.total_amount_cents).to eq(12)

        expect(result.invoice).to be_finalized
      end
    end
  end
end
