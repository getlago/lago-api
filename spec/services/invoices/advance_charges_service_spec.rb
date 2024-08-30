# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::AdvanceChargesService, type: :service do
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
      allow(Invoices::TransitionToFinalStatusService).to receive(:call).and_call_original
    end

    context 'with existing standalone fees' do
      before do
        tax
        charge = create(:standard_charge, :regroup_paid_fees, plan: subscription.plan)
        succeeded_fees = create_list(:charge_fee, 3, :succeeded, invoice_id: nil, subscription:, charge:, amount_cents: 100, properties: fee_boundaries)
        create_list(:charge_fee, 2, :failed, invoice_id: nil, subscription:, charge:, amount_cents: 100, properties: fee_boundaries)

        succeeded_fees.each { |fee| Fees::ApplyTaxesService.call(fee:) }
      end

      it 'creates invoices' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.count).to eq 3

          expect(result.invoice.total_amount_cents).to eq(100 * 3 * (100 + tax_rate) / 100)

          expect(result.invoice).to be_finalized.and(have_attributes({
            invoice_type: 'advance_charges',
            currency: 'EUR',
            issuing_date: billing_at.to_date,
            skip_charges: true,
            taxes_rate: tax_rate
          }))

          expect(result.invoice.invoice_subscriptions.count).to eq(1)
          sub = result.invoice.invoice_subscriptions.first
          expect(sub.charges_to_datetime).to match_datetime fee_boundaries[:charges_to_datetime]
          expect(sub.charges_from_datetime).to match_datetime fee_boundaries[:charges_from_datetime]
          expect(sub.invoicing_reason).to eq 'in_advance_charge_periodic'

          expect(SendWebhookJob).to have_been_enqueued.with('invoice.created', result.invoice)
          expect(Invoices::GeneratePdfAndNotifyJob).to have_been_enqueued.with(invoice: result.invoice, email: false)
          expect(SendWebhookJob).to have_been_enqueued.with('invoice.created', result.invoice)
          expect(SegmentTrackJob).to have_been_enqueued.once
          expect(Invoices::TransitionToFinalStatusService).to have_received(:call).with(invoice: result.invoice)
        end
      end
    end

    context 'without any standalone fees' do
      it 'does not create an invoice' do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice).to be_nil
      end
    end

    context 'with integration requiring sync' do
      before do
        tax
        charge = create(:standard_charge, :regroup_paid_fees, plan: subscription.plan)
        create(:charge_fee, :succeeded, invoice_id: nil, subscription:, charge:, amount_cents: 100, properties: fee_boundaries)

        allow_any_instance_of(Invoice).to receive(:should_sync_invoice?).and_return(true) # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(Invoice).to receive(:should_sync_sales_order?).and_return(true) # rubocop:disable RSpec/AnyInstance
      end

      it 'creates invoices' do
        result = invoice_service.call

        expect(Integrations::Aggregator::Invoices::CreateJob).to have_been_enqueued.with(invoice: result.invoice)
        expect(Integrations::Aggregator::SalesOrders::CreateJob).to have_been_enqueued.with(invoice: result.invoice)
      end
    end
  end
end
