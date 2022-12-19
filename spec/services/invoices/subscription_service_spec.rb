# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::SubscriptionService, type: :service do
  subject(:invoice_service) do
    described_class.new(
      subscriptions: subscriptions,
      timestamp: timestamp.to_i,
      recurring: true,
    )
  end

  describe 'create' do
    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        subscription_at: started_at.to_date,
        started_at: started_at,
        created_at: started_at,
      )
    end
    let(:subscriptions) { [subscription] }

    let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
    let(:timestamp) { Time.zone.now.beginning_of_month }
    let(:started_at) { Time.zone.now - 2.years }

    let(:plan) { create(:plan, interval: 'monthly', pay_in_advance: pay_in_advance) }
    let(:pay_in_advance) { false }

    before do
      create(:standard_charge, plan: subscription.plan, charge_model: 'standard')

      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::Payments::StripeCreateJob).to receive(:perform_later).and_call_original
      allow(Invoices::Payments::GocardlessCreateJob).to receive(:perform_later).and_call_original
    end

    it 'calls SegmentTrackJob' do
      invoice = invoice_service.create.invoice

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
      allow(Invoices::Payments::CreateService)
        .to receive(:new).and_return(payment_create_service)
      allow(payment_create_service)
        .to receive(:call)

      invoice_service.create

      expect(Invoices::Payments::CreateService).to have_received(:new)
      expect(payment_create_service).to have_received(:call)
    end

    it 'creates an invoice' do
      result = invoice_service.create

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice.invoice_subscriptions.first.properties['to_datetime'])
          .to eq (timestamp - 1.day).end_of_day.as_json
        expect(result.invoice.invoice_subscriptions.first.properties['from_datetime'])
          .to eq (timestamp - 1.month).beginning_of_day.as_json

        expect(result.invoice.subscriptions.first).to eq(subscription)
        expect(result.invoice.issuing_date.to_date).to eq(timestamp)
        expect(result.invoice.invoice_type).to eq('subscription')
        expect(result.invoice.payment_status).to eq('pending')
        expect(result.invoice.fees.subscription_kind.count).to eq(1)
        expect(result.invoice.fees.charge_kind.count).to eq(1)

        expect(result.invoice.amount_cents).to eq(100)
        expect(result.invoice.amount_currency).to eq('EUR')
        expect(result.invoice.vat_amount_cents).to eq(20)
        expect(result.invoice.vat_amount_currency).to eq('EUR')
        expect(result.invoice.vat_rate).to eq(20)
        expect(result.invoice.credit_amount_cents).to eq(0)
        expect(result.invoice.credit_amount_currency).to eq('EUR')
        expect(result.invoice.total_amount_cents).to eq(120)
        expect(result.invoice.total_amount_currency).to eq('EUR')

        expect(result.invoice).not_to be_legacy
      end
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        invoice_service.create
      end.to have_enqueued_job(SendWebhookJob).with(:invoice, Invoice)
    end

    context 'when organization does not have a webhook url' do
      before { subscription.customer.organization.update!(webhook_url: nil) }

      it 'does not enqueue a SendWebhookJob' do
        expect do
          invoice_service.create
        end.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'with customer timezone' do
      before { subscription.customer.update!(timezone: 'America/Los_Angeles') }

      let(:timestamp) { DateTime.parse('2022-11-25 01:00:00') }

      it 'assigns the issuing date in the customer timezone' do
        result = invoice_service.create

        expect(result.invoice.issuing_date.to_s).to eq('2022-11-24')
      end
    end
  end
end
