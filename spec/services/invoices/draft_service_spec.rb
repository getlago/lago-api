# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::DraftService do
  subject(:draft_service) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:, plan: plan) }
  let!(:invoice) { create(:invoice, organization:, customer:) }
  let!(:invoice_subscription) { create(:invoice_subscription, invoice:, subscription:) }
  let(:plan) { create(:plan, organization: organization) }

  describe "call" do
    context "with subscription fees" do
      let!(:fee) do
        create(
          :fee,
          invoice:,
          subscription:,
          fee_type: "subscription",
          units: 1,
          amount_cents: 1000,
          amount_currency: "EUR"
        )
      end

      it "creates a draft invoice with estimated fees" do
        result = draft_service.call

        expect(result).to be_success
        expect(result.invoice.id).to eq(invoice.id)
        expect(result.invoice.fees.size).to eq(1)
      end

      it "calls EstimateService for each fee" do
        expect(::AdjustedFees::EstimateService).to receive(:call).with(
          invoice: invoice,
          params: {
            invoice_subscription_id: fee.subscription_id,
            fee_type: fee.fee_type,
            units: fee.units,
            unit_precise_amount: fee.amount.currency.subunit_to_unit,
            charge_id: nil
          }
        ).and_call_original

        draft_service.call
      end

      context "when exists taxes" do
        let(:tax) { create(:tax, organization:, rate: 10, applied_to_organization: false) }
        let(:applied_tax) { create(:plan_applied_tax, plan:, tax: tax) }

        before { applied_tax }

        it "assigns ids to applied taxes" do
          result = draft_service.call
          expect(result.invoice.applied_taxes.first.id).to be_present
          expect(result.invoice.applied_taxes.first.invoice_id).to eq(invoice.id)
        end
      end
    end

    context "with charge fees" do
      let(:charge) { create(:standard_charge, plan: subscription.plan) }
      let!(:fee) do
        create(
          :charge_fee,
          invoice:,
          subscription:,
          charge:,
          fee_type: "charge",
          units: 5,
          amount_cents: 500
        )
      end

      it "calls EstimateService with charge fee parameters" do
        expect(::AdjustedFees::EstimateService).to receive(:call).with(
          invoice: invoice,
          params: {
            invoice_subscription_id: fee.subscription_id,
            fee_type: fee.fee_type,
            units: fee.units,
            unit_precise_amount: fee.amount.currency.subunit_to_unit,
            charge_id: fee.charge_id
          }
        ).and_call_original

        draft_service.call
      end
    end

    context "with multiple fees" do
      let(:subscription_fee) do
        create(:fee, invoice:, subscription:, fee_type: "subscription", units: 1, amount_cents: 1000)
      end

      let(:charge) { create(:standard_charge, plan: subscription.plan) }
      let(:charge_fee) do
        create(:charge_fee, invoice:, subscription:, charge:, fee_type: "charge", units: 5, amount_cents: 500)
      end

      before do
        subscription_fee
        charge_fee
        invoice_subscription
      end

      it "preserves fee ids from the original invoice" do
        result = draft_service.call

        fee_ids = result.invoice.fees.map(&:id)
        expect(fee_ids).to match_array([subscription_fee.id, charge_fee.id])
      end
    end
  end
end
