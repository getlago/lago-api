# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::ComputeAmountsFromFees do
  subject(:compute_amounts) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }

  let(:tax1) { create(:tax, :applied_to_billing_entity, organization:, rate: 10) }
  let(:tax2) { create(:tax, :applied_to_billing_entity, organization:, rate: 20) }

  let(:fee1) { create(:fee, invoice:, amount_cents: 151) }
  let(:fee2) { create(:fee, invoice:, amount_cents: 379, precise_coupons_amount_cents: 100) }

  before do
    tax1
    tax2

    fee1
    fee2

    create(:credit, invoice:, amount_cents: 100)
  end

  it "applied taxes to the fees" do
    compute_amounts.call

    expect(fee1.reload.applied_taxes.count).to eq(2)
    expect(fee1.taxes_rate).to eq(30)
    expect(fee1.taxes_amount_cents).to eq(45) # 151 * (10 + 20) / 100

    expect(fee2.reload.applied_taxes.count).to eq(2)
    expect(fee2.taxes_rate).to eq(30)
    expect(fee2.taxes_amount_cents).to eq(84) # (379 - 100) * (10 + 20) / 100
  end

  it "sets fees_amount_cents from the list of fees" do
    expect { compute_amounts.call }.to change(invoice, :fees_amount_cents).from(0).to(530)
  end

  it "sets coupons_amount_cents from the list of fees" do
    expect { compute_amounts.call }.to change(invoice, :coupons_amount_cents).from(0).to(100)
  end

  it "sets sub_total_excluding_taxes_amount_cents from the list of fees" do
    expect { compute_amounts.call }.to change(invoice, :sub_total_excluding_taxes_amount_cents).from(0).to(430)
  end

  it "sets taxes_amount_cents from the list of fees" do
    expect { compute_amounts.call }.to change(invoice, :taxes_amount_cents).from(0).to(129)
  end

  it "sets sub_total_including_taxes_amount_cents" do
    expect { compute_amounts.call }.to change(invoice, :sub_total_including_taxes_amount_cents).from(0).to(559)
  end

  it "sets total_amount_cents" do
    expect { compute_amounts.call }.to change(invoice, :total_amount_cents).from(0).to(559)
  end

  context "when invoice is not persisted and has no persisted fees" do
    subject { described_class.new(invoice: draft_invoice) }

    let(:draft_invoice) { build(:invoice, organization:, customer:, fees: fees) }
    let(:fees) do
      [build(:fee, amount_cents: 100), build(:fee, amount_cents: 150)]
    end

    it "avoids persisting fees" do
      result = subject.call

      expect(result.invoice.fees.length).to eq(2)
      expect(result.invoice.fees.map(&:id)).to eq([nil, nil])
    end

    it "calculates taxes amounts" do
      result = subject.call

      expect(result.invoice.taxes_rate).to eq(30)
    end
  end

  context "when invoice is one_off" do
    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :one_off) }

    it "applies taxes to fees regardless of invoice status" do
      compute_amounts.call

      expect(fee1.reload.applied_taxes.count).to eq(2)
      expect(fee1.taxes_rate).to eq(30)
    end

    context "when invoice is pending (deferred tax resolution)" do
      let(:invoice) { create(:invoice, :pending, organization:, customer:, invoice_type: :one_off) }

      it "applies taxes to fees" do
        compute_amounts.call

        expect(fee1.reload.applied_taxes.count).to eq(2)
      end
    end

    context "when invoice is failed" do
      let(:invoice) { create(:invoice, :failed, organization:, customer:, invoice_type: :one_off) }

      it "applies taxes to fees" do
        compute_amounts.call

        expect(fee1.reload.applied_taxes.count).to eq(2)
      end
    end
  end

  context "when invoice is advance_charges" do
    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :advance_charges) }

    it "does not apply taxes to fees" do
      compute_amounts.call

      expect(fee1.reload.applied_taxes).to be_empty
    end
  end

  context "when taxes are fetched from external provider" do
    let(:integration) { create(:anrok_integration, organization:) }
    let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
    let(:fee2) { create(:fee, invoice: nil) }

    let(:fee_taxes) do
      build(:tax_result,
        item_id: fee1.id,
        item_code: "lago_default_b2b",
        tax_breakdown: [
          build(:tax_breakdown_item, name: "tax 1", type: "type1", rate: "0.50", tax_amount: 75.5),
          build(:tax_breakdown_item, name: "tax 2", type: "type2", rate: "0.30", tax_amount: 45.3)
        ])
    end

    before do
      integration_customer

      invoice.credits.destroy_all
    end

    it "creates fee and invoice applied taxes and calculate totals" do
      described_class.new(invoice:, provider_taxes: [fee_taxes]).call

      expect(fee1.reload.applied_taxes.count).to eq(2)
      expect(fee1.taxes_rate).to eq(80)
      expect(fee1.taxes_amount_cents).to eq(121)

      expect(invoice.fees_amount_cents).to eq(151)
      expect(invoice.sub_total_excluding_taxes_amount_cents).to eq(151)
      expect(invoice.taxes_amount_cents).to eq(121)
      expect(invoice.sub_total_including_taxes_amount_cents).to eq(272)
      expect(invoice.taxes_rate).to eq(80)
      expect(invoice.total_amount_cents).to eq(272)
    end

    context "with allocated provider taxes" do
      subject(:compute_provider_amounts) { described_class.new(invoice:, provider_taxes:).call }

      let(:charge) { create(:standard_charge, organization:) }
      let(:fee_amounts) { [333, 333, 334] }
      let(:fee1) { charge_fees.first }
      let(:charge_fees) do
        fee_amounts.map { |amount| create(:charge_fee, invoice:, charge:, amount_cents: amount, precise_amount_cents: amount) }
      end
      let(:breakdown) { [["VAT", "0.10", 100]] }
      let(:provider_total) { 100 }
      let(:expected_fee_taxes) { [33, 33, 34] }
      let(:expected_jurisdictions) { {"VAT" => 100} }
      let(:group_taxes) do
        build(:tax_result, tax_amount_cents: provider_total, tax_breakdown: breakdown.map do |name, rate, amount|
          build(:tax_breakdown_item, name:, type: "tax", rate:, tax_amount: amount)
        end)
      end
      let(:provider_taxes) do
        Integrations::Aggregator::Taxes::Invoices::ChargeFeeGroup.new(fees: charge_fees).split_taxes(group_taxes)
      end

      shared_examples "reconciled provider taxes" do
        it "preserves fee, jurisdiction and invoice totals" do
          compute_provider_amounts

          fee_taxes = charge_fees.map { |fee| fee.reload.taxes_amount_cents }
          expect(fee_taxes).to eq(expected_fee_taxes)
          expect(charge_fees.map { |fee| fee.applied_taxes.sum(&:amount_cents) }).to eq(fee_taxes)
          expect(invoice.taxes_amount_cents).to eq(fee_taxes.sum)
          expect(invoice.applied_taxes.to_h { |tax| [tax.tax_name, tax.amount_cents] }).to eq(expected_jurisdictions)
          expect(charge_fees.flat_map(&:applied_taxes).group_by(&:tax_name)
            .transform_values { |taxes| taxes.sum(&:amount_cents) }).to eq(expected_jurisdictions)
        end
      end

      include_examples "reconciled provider taxes"

      context "with different jurisdiction rates" do
        let(:fee_amounts) { [268, 25] }
        let(:breakdown) { [["State", "0.06", 18], ["City", "0.02", 6]] }
        let(:provider_total) { 24 }
        let(:expected_fee_taxes) { [21, 3] }
        let(:expected_jurisdictions) { {"State" => 18, "City" => 6} }

        include_examples "reconciled provider taxes"
      end

      context "with three jurisdictions and two fees" do
        let(:fee_amounts) { [100, 100] }
        let(:breakdown) { %w[State County City].map { |name| [name, "0.025", 5] } }
        let(:provider_total) { 15 }
        let(:expected_fee_taxes) { [9, 6] }
        let(:expected_jurisdictions) { {"State" => 5, "County" => 5, "City" => 5} }

        include_examples "reconciled provider taxes"

        context "with fifty fees" do
          let(:fee_amounts) { Array.new(50, 100) }
          let(:breakdown) { %w[State County City].map { |name| [name, "0.025", 125] } }
          let(:provider_total) { 375 }
          let(:expected_fee_taxes) { Array.new(25, 9) + Array.new(25, 6) }
          let(:expected_jurisdictions) { {"State" => 125, "County" => 125, "City" => 125} }

          include_examples "reconciled provider taxes"

          it "retains fractional cents on every fee and jurisdiction" do
            compute_provider_amounts

            expect(charge_fees.map { |fee| fee.reload.taxes_precise_amount_cents }).to eq(Array.new(50, 7.5.to_d))
            expect(charge_fees.flat_map(&:applied_taxes).map(&:precise_amount_cents)).to eq(Array.new(150, 2.5.to_d))
            expect(charge_fees.map(&:taxes_base_rate)).to eq(Array.new(50, 1))
          end
        end
      end

      context "with ungrouped fees" do
        let(:charge_fees) do
          [create(:charge_fee, invoice:, charge:, amount_cents: 100, precise_amount_cents: 100),
            create(:add_on_fee, invoice:, amount_cents: 100, precise_amount_cents: 100)]
        end
        let(:breakdown) { %w[State County City].map { |name| [name, "0.025", 2.5] } }
        let(:provider_total) { 8 }
        let(:expected_fee_taxes) { [8, 8] }
        let(:expected_jurisdictions) { {"State" => 6, "County" => 6, "City" => 4} }
        let(:provider_taxes) { charge_fees.map { |fee| group_taxes.with(item_key: fee.item_key, item_id: fee.id) } }

        include_examples "reconciled provider taxes"
      end
    end

    context "when provider taxes are not provided" do
      subject(:compute_amounts) { described_class.new(invoice:, provider_taxes: nil) }

      before do
        allow(invoice).to receive(:should_apply_provider_tax?).and_return(true)
        allow(Invoices::ApplyProviderTaxesService).to receive(:call!)
        allow(Invoices::ApplyTaxesService).to receive(:call!).and_call_original
      end

      it "applies regular taxes without fetching provider taxes" do
        compute_amounts.call

        expect(Invoices::ApplyProviderTaxesService).not_to have_received(:call!)
        expect(Invoices::ApplyTaxesService).to have_received(:call!).with(invoice:)
      end
    end
  end
end
