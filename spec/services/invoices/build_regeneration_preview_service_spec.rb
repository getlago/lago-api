# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::BuildRegenerationPreviewService do
  subject(:preview_service) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:, plan:) }
  let(:invoice) { create(:invoice, organization:, customer:, taxes_rate: 10) }
  let(:invoice_subscription) { create(:invoice_subscription, invoice:, subscription:) }

  describe "#call" do
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

    before do
      allow(Fees::ApplyTaxesService).to receive(:call!).and_call_original
      allow(Invoices::ComputeAmountsFromFees).to receive(:call).and_call_original

      invoice_subscription
      fee
    end

    it "builds a preview invoice with fees" do
      result = preview_service.call

      expect(result).to be_success
      expect(result.invoice.id).to eq(invoice.id)
      expect(result.invoice.fees.size).to eq(1)
      expect(result.invoice.taxes_rate).to eq(0)
    end

    it "calls ApplyTaxesService for fee" do
      preview_service.call

      expect(Fees::ApplyTaxesService).to have_received(:call!).at_least(:once).with(fee:)
    end

    it "does not apply provider taxes" do
      preview_service.call

      expect(Invoices::ComputeAmountsFromFees).to have_received(:call).with(
        invoice: be_a(Invoice),
        provider_taxes: nil
      )
    end

    context "when the customer has a tax customer" do
      let(:integration) { create(:anrok_integration, organization:) }

      before do
        create(:anrok_customer, integration:, customer:)
        allow(Invoices::ApplyProviderTaxesService).to receive(:call!)
      end

      it "does not apply provider taxes" do
        preview_service.call

        expect(Invoices::ApplyProviderTaxesService).not_to have_received(:call!)
      end
    end

    context "with multiple fees" do
      let(:charge) { create(:standard_charge, plan:) }
      let(:charge_fee) do
        create(
          :charge_fee,
          invoice:,
          subscription:,
          charge:,
          fee_type: "charge",
          units: 3,
          amount_cents: 300,
          taxes_rate: 10,
          amount_currency: "EUR"
        )
      end

      before { charge_fee }

      it "builds a preview invoice with all fees" do
        result = preview_service.call

        expect(result).to be_success
        expect(result.invoice.fees.size).to eq(2)
      end

      it "calls ApplyTaxesService for each fee" do
        preview_service.call

        expect(Fees::ApplyTaxesService).to have_received(:call!).at_least(:once).with(fee:)
        expect(Fees::ApplyTaxesService).to have_received(:call!).at_least(:once).with(fee: charge_fee)
      end
    end

    context "when a charge price changed after invoicing" do
      let(:parent_plan) { create(:plan, organization:) }
      let(:parent_charge) { create(:standard_charge, plan: parent_plan, organization:, properties: {amount: "0"}) }
      let(:plan) { create(:plan, organization:, parent: parent_plan) }
      let(:charge) do
        create(
          :standard_charge,
          plan:,
          organization:,
          parent: parent_charge,
          prorated: true,
          properties: {amount: "2000"}
        )
      end
      let(:fee) do
        create(
          :charge_fee,
          invoice:,
          subscription:,
          charge:,
          fee_type: "charge",
          units: 1,
          amount_cents: 0,
          precise_amount_cents: 0,
          unit_amount_cents: 0,
          precise_unit_amount: 0,
          taxes_rate: 10,
          amount_currency: "EUR"
        )
      end

      it "uses the current overridden charge price without persisting or changing the original fee" do
        result = preview_service.call
        preview_fee = result.invoice.fees.sole

        expect(preview_fee).to have_attributes(
          id: fee.id,
          charge_id: charge.id,
          units: 1,
          unit_amount_cents: 200_000,
          precise_unit_amount: 2000,
          amount_cents: 200_000
        )
        expect(preview_fee).not_to be_persisted
        expect(fee.reload).to have_attributes(unit_amount_cents: 0, precise_unit_amount: 0, amount_cents: 0)
        expect(invoice.reload.fees).to contain_exactly(fee)
      end

      context "with an explicit zero price adjustment" do
        before do
          create(
            :adjusted_fee,
            organization:,
            invoice:,
            fee:,
            subscription:,
            charge:,
            fee_type: :charge,
            adjusted_units: false,
            adjusted_amount: true,
            units: 1,
            unit_amount_cents: 0,
            unit_precise_amount_cents: 0,
            properties: fee.properties,
            grouped_by: {}
          )
        end

        it "keeps the explicit price adjustment" do
          preview_fee = preview_service.call.invoice.fees.sole

          expect(preview_fee).to have_attributes(
            units: 1,
            unit_amount_cents: 0,
            precise_unit_amount: 0,
            amount_cents: 0
          )
        end
      end
    end

    context "when a charge price is unchanged" do
      let(:charge) { create(:standard_charge, plan:, properties: {amount: "10"}) }
      let(:fee) do
        create(
          :charge_fee,
          invoice:,
          subscription:,
          charge:,
          units: 2,
          amount_cents: 2000,
          precise_amount_cents: 2000,
          unit_amount_cents: 1000,
          precise_unit_amount: 10,
          amount_currency: "EUR"
        )
      end

      it "keeps the same charge fee amounts" do
        preview_fee = preview_service.call.invoice.fees.sole

        expect(preview_fee).to have_attributes(
          units: 2,
          unit_amount_cents: 1000,
          precise_unit_amount: 10,
          amount_cents: 2000
        )
      end
    end

    context "with taxes" do
      let(:tax) { create(:tax, organization:, rate: 12, applied_to_organization: false) }
      let(:applied_tax) { create(:plan_applied_tax, plan:, tax:) }

      before { applied_tax }

      it "applies taxes and assigns ids to applied taxes" do
        result = preview_service.call
        preview_applied_tax = result.invoice.applied_taxes.first

        expect(preview_applied_tax).not_to be_nil
        expect(preview_applied_tax.id).to be_present
        expect(preview_applied_tax.invoice_id).to eq(invoice.id)
        expect(preview_applied_tax.tax_rate).to eq(12)
        expect(result.invoice.taxes_rate).to eq(12)
      end

      it "assigns ids and original fee ids to fee applied taxes" do
        result = preview_service.call
        preview_fee = result.invoice.fees.find { |result_fee| result_fee.id == fee.id }
        preview_fee_applied_tax = preview_fee.applied_taxes.first

        expect(preview_fee_applied_tax).not_to be_nil
        expect(preview_fee_applied_tax.id).to be_present
        expect(preview_fee_applied_tax.fee_id).to eq(fee.id)
        expect(preview_fee_applied_tax.tax_rate).to eq(12)
      end
    end
  end
end
