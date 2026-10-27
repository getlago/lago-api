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

  describe "#call with charge fees priced again" do
    subject(:result) { preview_service.call }

    let(:invoice) { create(:invoice, :voided, organization:, customer:, currency: "EUR") }
    let(:subscription) do
      create(:subscription, customer:, organization:, plan:, started_at: Time.zone.parse("2024-01-01"))
    end
    let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }
    let(:current_amount) { "10" }
    let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: current_amount}) }
    let(:fee_properties) do
      {
        "timestamp" => "2024-04-01T00:00:00.000Z",
        "from_datetime" => "2024-03-01T00:00:00.000Z",
        "to_datetime" => "2024-03-31T23:59:59.999Z",
        "charges_from_datetime" => "2024-03-01T00:00:00.000Z",
        "charges_to_datetime" => "2024-03-31T23:59:59.999Z",
        "charges_duration" => 31
      }
    end
    let(:voided_amount_cents) { 1500 }
    let(:charge_fee) do
      create(
        :charge_fee,
        invoice:,
        organization:,
        subscription:,
        charge:,
        units: 3,
        total_aggregated_units: 3,
        events_count: 1,
        amount_cents: voided_amount_cents,
        precise_amount_cents: voided_amount_cents,
        unit_amount_cents: 500,
        precise_unit_amount: 5,
        amount_currency: "EUR",
        properties: fee_properties
      )
    end
    let(:subscription_fee) do
      create(
        :fee,
        invoice:,
        organization:,
        subscription:,
        fee_type: "subscription",
        units: 1,
        amount_cents: 1000,
        amount_currency: "EUR"
      )
    end

    let(:preview_charge_fee) { result.invoice.fees.find { |preview_fee| preview_fee.id == charge_fee.id } }

    before do
      create(:invoice_subscription, invoice:, subscription:)
      create(
        :event,
        organization_id: organization.id,
        subscription:,
        code: billable_metric.code,
        timestamp: Time.zone.parse("2024-03-10T12:00:00"),
        properties: {value: 3}
      )
      charge_fee
      subscription_fee
    end

    context "when the charge price changed" do
      it "prices the fee with the current price" do
        expect(preview_charge_fee).to have_attributes(
          units: 3,
          amount_cents: 3000,
          unit_amount_cents: 1000,
          precise_unit_amount: 10,
          charge_id: charge.id
        )
        expect(result.invoice.fees_amount_cents).to eq(4000)
      end

      it "keeps the non-charge fee unchanged" do
        preview_subscription_fee = result.invoice.fees.find { |preview_fee| preview_fee.id == subscription_fee.id }

        expect(preview_subscription_fee).to have_attributes(units: 1, amount_cents: 1000)
      end

      it "persists nothing" do
        expect { result }
          .to not_change(Fee, :count)
          .and not_change(AdjustedFee, :count)
          .and not_change(Invoice, :count)
          .and not_change(PricingUnitUsage, :count)
      end

      it "leaves the voided invoice and its fees unchanged" do
        result

        expect(invoice.reload.fees_amount_cents).to eq(invoice.fees_amount_cents)
        expect(charge_fee.reload).to have_attributes(units: 3, amount_cents: 1500, precise_unit_amount: 5)
        expect(result.invoice.fees.size).to eq(invoice.fees.count)
      end
    end

    context "when the price did not change" do
      let(:current_amount) { "5" }

      it "returns the voided amounts" do
        expect(preview_charge_fee).to have_attributes(units: 3, amount_cents: 1500, precise_unit_amount: 5)
      end
    end

    context "with a manual adjustment" do
      let(:voided_amount_cents) { 0 }

      before do
        create(
          :adjusted_fee,
          organization:,
          invoice:,
          fee: charge_fee,
          subscription:,
          charge:,
          fee_type: :charge,
          units: 3,
          unit_amount_cents: 0,
          unit_precise_amount_cents: 0,
          adjusted_units: false,
          adjusted_amount: true
        )
      end

      it "keeps the adjusted price" do
        expect(preview_charge_fee).to have_attributes(units: 3, amount_cents: 0)
      end
    end

    context "with a true-up fee" do
      let(:true_up_fee) do
        create(
          :charge_fee,
          invoice:,
          organization:,
          subscription:,
          charge:,
          true_up_parent_fee: charge_fee,
          units: 1,
          amount_cents: 700,
          amount_currency: "EUR",
          properties: fee_properties
        )
      end

      before { true_up_fee }

      it "keeps the true-up amount" do
        preview_true_up_fee = result.invoice.fees.find { |preview_fee| preview_fee.id == true_up_fee.id }

        expect(preview_true_up_fee).to have_attributes(units: 1, amount_cents: 700)
        expect(preview_charge_fee.amount_cents).to eq(3000)
      end
    end

    context "when the charge is discarded" do
      before { charge.discard! }

      it "keeps the historical values" do
        expect(preview_charge_fee).to have_attributes(units: 3, amount_cents: 1500, precise_unit_amount: 5)
      end
    end

    context "when the charge filter is discarded" do
      let(:charge_filter) { create(:charge_filter, charge:, properties: {amount: current_amount}) }
      let(:charge_fee) do
        create(
          :charge_fee,
          invoice:,
          organization:,
          subscription:,
          charge:,
          charge_filter:,
          units: 3,
          amount_cents: 1500,
          precise_amount_cents: 1500,
          unit_amount_cents: 500,
          precise_unit_amount: 5,
          amount_currency: "EUR",
          properties: fee_properties
        )
      end

      before { charge_filter.discard! }

      it "keeps the historical values" do
        expect(preview_charge_fee).to have_attributes(units: 3, amount_cents: 1500, precise_unit_amount: 5)
      end
    end

    context "with a pay in advance fee" do
      let(:charge_fee) do
        create(
          :charge_fee,
          invoice:,
          organization:,
          subscription:,
          charge:,
          pay_in_advance: true,
          units: 3,
          amount_cents: 1500,
          amount_currency: "EUR",
          properties: fee_properties
        )
      end

      it "keeps the historical values" do
        expect(preview_charge_fee).to have_attributes(units: 3, amount_cents: 1500)
      end
    end

    context "with a progressive billing invoice" do
      let(:invoice) do
        create(:invoice, :voided, organization:, customer:, currency: "EUR", invoice_type: :progressive_billing)
      end

      it "keeps the historical values" do
        expect(preview_charge_fee).to have_attributes(units: 3, amount_cents: 1500)
      end
    end
  end
end
