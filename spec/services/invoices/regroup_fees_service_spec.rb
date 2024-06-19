# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::RegroupFeesService, type: :service do
  subject(:invoice_service) { described_class.new(subscriptions:, billing_at:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax_rate) { 20 }
  let(:tax) { create(:tax, organization:, rate: tax_rate) }

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

    let(:billable_metric) { create(:billable_metric, code: 'new_user') }
    let(:billing_at) { Time.zone.now.beginning_of_month + 1.hour }
    let(:started_at) { Time.zone.now - 2.years }

    let(:plan) { create(:plan, interval: 'monthly', pay_in_advance: true) }

    def fee_boundaries
      prev_month = billing_at - 1.month
      charges_from_datetime = prev_month.beginning_of_month
      charges_to_datetime = prev_month.end_of_month

      {
        timestamp: rand(charges_from_datetime..charges_to_datetime),
        charges_from_datetime:,
        charges_to_datetime:
      }
    end

    before do
      allow(Invoices::Payments::CreateService).to receive(:call)
    end

    context 'with existing standalone fees' do
      before do
        tax
        charge = create(:standard_charge, plan: subscription.plan, charge_model: 'standard')
        create_list(:charge_fee, 3, :succeeded, invoice_id: nil, subscription:, charge:, amount_cents: 100, properties: fee_boundaries)
        create_list(:charge_fee, 2, :failed, invoice_id: nil, subscription:, charge:, amount_cents: 100, properties: fee_boundaries)
      end

      it 'creates invoices' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoices.count).to eq(2)

          paid_invoice = result.invoices.find { |i| i.payment_status == 'succeeded' }
          pending_invoice = result.invoices.find { |i| i.payment_status == 'pending' }

          expect(paid_invoice.fees.count).to eq 3
          expect(pending_invoice.fees.count).to eq 2

          expect(paid_invoice.total_amount_cents).to eq(100 * 3 * (100 + tax_rate) / 100)

          expect(result.invoices).to all(be_finalized).and(all(have_attributes({
            invoice_type: 'grouped_in_advance_charges',
            currency: 'EUR',
            issuing_date: billing_at.to_date,
            skip_charges: true,
            taxes_rate: tax_rate
          })))

          result.invoices.each do |i|
            expect(i.invoice_subscriptions.count).to eq(1)
            sub = i.invoice_subscriptions.first
            expect(sub.charges_to_datetime).to match_datetime fee_boundaries[:charges_to_datetime]
            expect(sub.charges_from_datetime).to match_datetime fee_boundaries[:charges_from_datetime]
            expect(sub.invoicing_reason).to eq 'in_advance_charge_periodic'

            expect(SendWebhookJob).to have_been_enqueued.with('invoice.created', i)
            expect(Invoices::GeneratePdfAndNotifyJob).to have_been_enqueued.with(invoice: i, email: false)
            expect(SendWebhookJob).to have_been_enqueued.with('invoice.created', i)
          end

          expect(Invoices::Payments::CreateService).to have_received(:call).once
          expect(SegmentTrackJob).to have_been_enqueued.twice

          # TODO: Add expectations around webhook, PDF, sync, and segment track
        end
      end
    end

    context 'without any standalone fees' do
      it 'does not create an invoice' do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoices).to be_empty
      end
    end

    context 'with integration requiring sync' do
      before do
        tax
        charge = create(:standard_charge, plan: subscription.plan, charge_model: 'standard')
        create(:charge_fee, :succeeded, invoice_id: nil, subscription:, charge:, amount_cents: 100, properties: fee_boundaries)

        allow_any_instance_of(Invoice).to receive(:should_sync_invoice?).and_return(true)
        allow_any_instance_of(Invoice).to receive(:should_sync_sales_order?).and_return(true)
      end

      it 'creates invoices' do
        result = invoice_service.call

        result.invoices.each do |i|
          expect(Integrations::Aggregator::Invoices::CreateJob).to have_been_enqueued.with(invoice: i)
          expect(Integrations::Aggregator::SalesOrders::CreateJob).to have_been_enqueued.with(invoice: i)
        end
      end
    end
  end
end
