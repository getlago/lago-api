# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::AdvanceChargesService, type: :service do
  subject(:invoice_service) do
    described_class.new(initial_subscriptions: subscriptions, billing_at:)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax_rate) { 20 }
  let(:tax) { create(:tax, organization:, rate: tax_rate) }

  describe "#call" do
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

    let(:billable_metric) { create(:billable_metric, organization:, code: "new_user") }
    let(:billing_at) { Time.zone.now.beginning_of_month + 1.hour }
    let(:started_at) { Time.zone.now - 2.years }

    let(:plan) { create(:plan, organization:, interval: "monthly", pay_in_advance: true) }

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
      allow(Invoices::Payments::CreateService).to receive(:call_async)
      allow(Invoices::TransitionToFinalStatusService).to receive(:call).and_call_original
    end

    context "with existing standalone fees" do
      before do
        tax
        charge = create(:standard_charge, :regroup_paid_fees, plan: subscription.plan)
        succeeded_fees = create_list(
          :charge_fee,
          3,
          organization_id: organization.id,
          payment_status: :succeeded,
          succeeded_at: billing_at - 1.month,
          invoice_id: nil,
          subscription:,
          charge:,
          amount_cents: 100,
          properties: fee_boundaries
        )
        create_list(:charge_fee, 2, :failed, invoice_id: nil, subscription:, charge:, amount_cents: 100, properties: fee_boundaries)

        create(
          :charge_fee,
          payment_status: :succeeded,
          succeeded_at: (billing_at - 1.month).end_of_month + 1.day,
          invoice_id: nil,
          subscription:,
          charge:,
          properties: {
            timestamp: (billing_at - 1.month).end_of_month + 1.day
          }
        )

        succeeded_fees.each { |fee| Fees::ApplyTaxesService.call(fee:) }
      end

      it "creates invoices" do
        result = invoice_service.call
        expect(result).to be_success

        expect(result.invoice.fees.count).to eq 3

        expect(result.invoice.total_amount_cents).to eq(100 * 3 * (100 + tax_rate) / 100)

        expect(result.invoice).to be_finalized.and(have_attributes({
          invoice_type: "advance_charges",
          currency: "EUR",
          issuing_date: billing_at.to_date,
          skip_charges: true,
          taxes_rate: tax_rate
        }))

        expect(result.invoice.invoice_subscriptions.count).to eq(1)
        sub = result.invoice.invoice_subscriptions.first
        expect(sub.charges_to_datetime).to match_datetime fee_boundaries[:charges_to_datetime]
        expect(sub.charges_from_datetime).to match_datetime fee_boundaries[:charges_from_datetime]
        expect(sub.invoicing_reason).to eq "in_advance_charge_periodic"

        expect(SendWebhookJob).to have_been_enqueued.with("invoice.created", result.invoice)
        expect(Invoices::GeneratePdfAndNotifyJob).to have_been_enqueued.with(invoice: result.invoice, email: false)
        expect(SendWebhookJob).to have_been_enqueued.with("invoice.created", result.invoice)
        expect(SegmentTrackJob).to have_been_enqueued.once
        expect(Invoices::TransitionToFinalStatusService).to have_received(:call).with(invoice: result.invoice)
      end
    end

    context "without any standalone fees" do
      it "does not create an invoice" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice).to be_nil
      end

      context "when there is a pay in advance charge" do
        before do
          create(:standard_charge, :regroup_paid_fees, plan: subscription.plan)
        end

        it "does not create an invoice" do
          result = invoice_service.call

          expect(result).to be_success
          expect(result.invoice).to be_nil
        end
      end
    end

    context "when there is a successful non invoiceable paid in advance fees" do
      let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }

      let(:charge) do
        create(
          :charge,
          plan:,
          billable_metric:,
          prorated: true,
          pay_in_advance: true,
          invoiceable: false,
          regroup_paid_fees: "invoice",
          properties: {amount: "1"}
        )
      end

      let(:subscription_2) do
        create(:subscription, {
          external_id: subscription.external_id,
          customer: subscription.customer,
          status: :terminated,
          started_at: Time.current - 1.year,
          plan:
        })
      end

      let(:paid_in_advance_fee) do
        create(
          :fee,
          :succeeded,
          organization_id: organization.id,
          succeeded_at: fee_boundaries[:charges_to_datetime] - 2.days,
          invoice_id: nil,
          subscription: subscription_2,
          amount_cents: 999,
          properties: fee_boundaries,
          charge:
        )
      end

      before { paid_in_advance_fee }

      it "creates invoices" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice).to be_a Invoice
        expect(result.invoice.fees.count).to eq 1
        expect(result.invoice.total_amount_cents).to eq(paid_in_advance_fee.amount_cents)

        expect(result.invoice)
          .to be_finalized
          .and have_attributes(
            invoice_type: "advance_charges",
            currency: "EUR",
            issuing_date: billing_at.to_date,
            skip_charges: true
          )

        expect(result.invoice.invoice_subscriptions.count).to eq(1)
        sub = result.invoice.invoice_subscriptions.first
        expect(sub.charges_to_datetime).to match_datetime fee_boundaries[:charges_to_datetime]
        expect(sub.charges_from_datetime).to match_datetime fee_boundaries[:charges_from_datetime]
        expect(sub.invoicing_reason).to eq "in_advance_charge_periodic"
      end
    end

    context "with integration requiring sync" do
      before do
        tax
        charge = create(:standard_charge, :regroup_paid_fees, plan: subscription.plan)
        create(
          :charge_fee,
          organization_id: organization.id,
          payment_status: :succeeded,
          succeeded_at: billing_at - 1.month,
          invoice_id: nil,
          subscription:,
          charge:,
          amount_cents: 100,
          properties: fee_boundaries
        )

        allow_any_instance_of(Invoice).to receive(:should_sync_invoice?).and_return(true) # rubocop:disable RSpec/AnyInstance
      end

      it "creates invoices" do
        result = invoice_service.call

        expect(Integrations::Aggregator::Invoices::CreateJob).to have_been_enqueued.with(invoice: result.invoice)
      end
    end
  end
end
