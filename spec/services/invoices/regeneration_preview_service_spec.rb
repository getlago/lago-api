# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::RegenerationPreviewService do
  subject(:draft_service) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:, plan: plan) }
  let(:invoice) { create(:invoice, organization:, customer:, taxes_rate: 10) }
  let(:invoice_subscription) { create(:invoice_subscription, invoice:, subscription:) }
  let(:plan) { create(:plan, organization: organization) }

  describe "#call" do
    before do
      invoice
      invoice_subscription

      allow(::AdjustedFees::EstimateService).to receive(:call).and_call_original
      allow(Integrations::Aggregator::Taxes::Invoices::CreateDraftService).to receive(:call).and_call_original
    end

    context "with subscription fees" do
      let(:fee) do
        create(
          :fee,
          invoice:,
          subscription:,
          fee_type: "subscription",
          units: 1,
          amount_cents: 1000,
          taxes_rate: 10,
          amount_currency: "EUR",
          invoice_display_name: "Subscription Fee"
        )
      end

      before { fee }

      it "builds a draft invoice with estimated fees" do
        result = draft_service.call

        expect(result).to be_success
        expect(result.invoice.id).to eq(invoice.id)
        expect(result.invoice.fees.size).to eq(1)
        expect(result.invoice.taxes_rate).to eq(0)
      end

      it "calls EstimateService for single fee" do
        result = draft_service.call

        expect(::AdjustedFees::EstimateService).to have_received(:call).once.with(
          invoice: invoice,
          params: {
            invoice_subscription_id: fee.subscription_id,
            fee_type: fee.fee_type,
            units: fee.units,
            unit_precise_amount: fee.amount.currency.subunit_to_unit,
            charge_id: nil,
            charge_filter_id: nil,
            fixed_charge_id: nil,
            invoice_display_name: "Subscription Fee"
          }
        )

        expect(result.invoice.fees.first.taxes_rate).to eq(0)
      end

      it "calls CreateDraftService with estimated fees" do
        draft_service.call

        expect(Integrations::Aggregator::Taxes::Invoices::CreateDraftService).to have_received(:call)
          .once.with(invoice: an_instance_of(Invoice), fees: an_instance_of(Array))
      end

      context "with taxes" do
        let(:tax) { create(:tax, organization:, rate: 12, applied_to_organization: false) }
        let(:applied_tax) { create(:plan_applied_tax, plan:, tax: tax) }

        before { applied_tax }

        it "assigns ids to applied taxes" do
          result = draft_service.call
          draft_applied_tax = result.invoice.applied_taxes.first

          expect(draft_applied_tax).not_to be_nil
          expect(draft_applied_tax.invoice_id).to eq(invoice.id)
          expect(draft_applied_tax.tax_rate).to eq(12)
          expect(result.invoice.taxes_rate).to eq(12)

          draft_fee = result.invoice.fees.first

          expect(draft_fee.taxes_rate).to eq(12)
        end
      end
    end

    context "with charge fees" do
      let(:charge) { create(:standard_charge, plan: subscription.plan) }
      let(:fee) do
        create(
          :charge_fee,
          invoice:,
          subscription:,
          charge:,
          fee_type: "charge",
          units: 5,
          taxes_rate: 10,
          amount_cents: 500,
          invoice_display_name: nil
        )
      end

      before { fee }

      it "calls EstimateService with charge fee parameters" do
        result = draft_service.call

        expect(::AdjustedFees::EstimateService).to have_received(:call).once.with(
          invoice: invoice,
          params: {
            invoice_subscription_id: fee.subscription_id,
            fee_type: fee.fee_type,
            units: fee.units,
            unit_precise_amount: fee.amount.currency.subunit_to_unit,
            charge_id: fee.charge_id,
            charge_filter_id: nil,
            fixed_charge_id: nil,
            invoice_display_name: nil
          }
        )

        expect(result.invoice.fees.first.taxes_rate).to eq(0)
      end
    end

    it "calls CreateDraftService with estimated fees" do
      draft_service.call

      expect(Integrations::Aggregator::Taxes::Invoices::CreateDraftService).to have_received(:call)
        .once.with(invoice: an_instance_of(Invoice), fees: an_instance_of(Array))
    end

    context "with fixed_charge fees" do
      let(:fixed_charge) { create(:fixed_charge, plan: subscription.plan) }
      let(:fee) do
        create(
          :fixed_charge_fee,
          invoice:,
          subscription:,
          fixed_charge:,
          fee_type: "fixed_charge",
          taxes_rate: 10,
          units: 1,
          amount_cents: 750
        )
      end

      before { fee }

      it "calls EstimateService with fixed_charge fee parameters" do
        result = draft_service.call

        expect(::AdjustedFees::EstimateService).to have_received(:call).once.with(
          invoice: invoice,
          params: {
            invoice_subscription_id: fee.subscription_id,
            fee_type: fee.fee_type,
            units: fee.units,
            unit_precise_amount: fee.amount.currency.subunit_to_unit,
            charge_id: nil,
            charge_filter_id: nil,
            fixed_charge_id: fee.fixed_charge_id,
            invoice_display_name: fee.invoice_display_name
          }
        )

        expect(result.invoice.fees.first.taxes_rate).to eq(0)
      end

      it "calls CreateDraftService with estimated fees" do
        draft_service.call

        expect(Integrations::Aggregator::Taxes::Invoices::CreateDraftService).to have_received(:call)
          .once.with(invoice: an_instance_of(Invoice), fees: an_instance_of(Array))
      end
    end
  end
end
