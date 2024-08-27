# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::ProgressiveBillingService, type: :service do
  subject(:create_service) { described_class.new(usage_thresholds:, lifetime_usage:, timestamp:) }

  let(:usage_thresholds) { [create(:usage_threshold, plan:)] }
  let(:plan) { create(:plan) }
  let(:organization) { plan.organization }

  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, plan:, customer:, started_at: timestamp - 1.week) }
  let(:lifetime_usage) { create(:lifetime_usage, subscription:, organization:) }

  let(:timestamp) { Time.zone.parse('2024-08-22 10:00:00') }

  let(:tax) { create(:tax, organization:, rate: 20) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: 'value') }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: '1'}) }

  let(:event) do
    create(
      :event,
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code: billable_metric.code,
      properties: {billable_metric.field_name => 1},
      timestamp: timestamp - 1.hour
    )
  end

  before do
    allow(SegmentTrackJob).to receive(:perform_later)

    tax
    charge
    event
  end

  describe '#call' do
    it 'creates a progressive billing invoice', aggregate_failures: true do
      result = create_service.call

      expect(result).to be_success
      expect(result.invoice).to be_present

      invoice = result.invoice
      amount_cents = 100

      expect(invoice).to be_persisted
      expect(invoice).to have_attributes(
        organization: organization,
        customer: customer,
        currency: plan.amount_currency,
        status: 'finalized',
        invoice_type: 'progressive_billing',
        fees_amount_cents: amount_cents,
        taxes_amount_cents: amount_cents * tax.rate / 100,
        total_amount_cents: amount_cents * (1 + tax.rate / 100)
      )

      expect(invoice.invoice_subscriptions.count).to eq(1)
      expect(invoice.fees.count).to eq(1)
      expect(invoice.applied_usage_thresholds.count).to eq(1)

      expect(invoice.applied_usage_thresholds.first.lifetime_usage_amount_cents)
        .to eq(lifetime_usage.total_amount_cents)
    end

    context 'with multiple thresholds' do
      let(:usage_thresholds) do
        [
          create(:usage_threshold, plan:, amount_cents: 1000),
          create(:usage_threshold, plan:, amount_cents: 2500)
        ]
      end

      it 'creates a progressive billing invoice', aggregate_failures: true do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to be_present

        invoice = result.invoice
        amount_cents = 100

        expect(invoice).to be_persisted
        expect(invoice).to have_attributes(
          organization: organization,
          customer: customer,
          currency: plan.amount_currency,
          status: 'finalized',
          invoice_type: 'progressive_billing',
          fees_amount_cents: amount_cents,
          taxes_amount_cents: amount_cents * tax.rate / 100,
          total_amount_cents: amount_cents * (1 + tax.rate / 100)
        )

        expect(invoice.invoice_subscriptions.count).to eq(1)
        expect(invoice.fees.count).to eq(1)
        expect(invoice.applied_usage_thresholds.count).to eq(2)
      end
    end

    context 'when threshold was already billed' do
      before do
        invoice = create(
          :invoice,
          organization:,
          customer:,
          status: 'finalized',
          invoice_type: :progressive_billing,
          fees_amount_cents: 20,
          subscriptions: [subscription],
          issuing_date: timestamp - 1.day
        )

        create(
          :charge_fee,
          invoice:,
          amount_cents: 20
        )
        invoice.invoice_subscriptions.first.update!(
          charges_from_datetime: invoice.issuing_date - 2.weeks,
          charges_to_datetime: invoice.issuing_date + 2.weeks,
          timestamp: invoice.issuing_date
        )
      end

      it 'creates a progressive billing invoice', aggregate_failures: true do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to be_present

        invoice = result.invoice
        amount_cents = 100

        expect(invoice).to be_persisted
        expect(invoice).to have_attributes(
          organization: organization,
          customer: customer,
          currency: plan.amount_currency,
          status: 'finalized',
          invoice_type: 'progressive_billing',
          fees_amount_cents: amount_cents,
          taxes_amount_cents: (amount_cents - 20) * tax.rate / 100,
          total_amount_cents: (amount_cents - 20) * (1 + tax.rate / 100)
        )

        expect(invoice.invoice_subscriptions.count).to eq(1)
        expect(invoice.credits.count).to eq(1)
        expect(invoice.fees.count).to eq(1)
      end
    end

    it 'enqueues a SendWebhookJob' do
      expect { create_service.call }.to have_enqueued_job(SendWebhookJob)
    end

    it 'enqueue an GeneratePdfAndNotifyJob with email false' do
      expect { create_service.call }
        .to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: false))
    end

    context 'with lago_premium' do
      around { |test| lago_premium!(&test) }

      it 'enqueues an GeneratePdfAndNotifyJob with email true' do
        expect { create_service.call }
          .to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: true))
      end

      context 'when organization does not have right email settings' do
        before { subscription.organization.update!(email_settings: []) }

        it 'enqueue an GeneratePdfAndNotifyJob with email false' do
          expect { create_service.call }
            .to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: false))
        end
      end
    end

    it 'calls SegmentTrackJob' do
      invoice = create_service.call.invoice

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type
        }
      )
    end

    it 'creates a payment' do
      allow(Invoices::Payments::CreateService).to receive(:call)

      create_service.call

      expect(Invoices::Payments::CreateService).to have_received(:call)
    end

    it_behaves_like 'syncs invoice' do
      let(:service_call) { create_service.call }
    end

    it_behaves_like 'syncs sales order' do
      let(:service_call) { create_service.call }
    end
  end
end
