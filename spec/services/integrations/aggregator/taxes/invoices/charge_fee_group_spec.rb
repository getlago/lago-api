# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Taxes::Invoices::ChargeFeeGroup do
  subject(:group) { described_class.new(fees: [fee1, fee2]) }

  let(:invoice) { build_stubbed(:invoice) }
  let(:charge) { build_stubbed(:standard_charge, organization: invoice.organization) }
  let(:coupon1) { 0 }
  let(:coupon2) { 0 }
  let(:fee1) do
    build_stubbed(:charge_fee, invoice:, charge:, units: 2, amount_cents: 300,
      precise_amount_cents: 300, precise_coupons_amount_cents: coupon1)
  end
  let(:fee2) do
    build_stubbed(:charge_fee, invoice:, charge:, units: 3, amount_cents: 700,
      precise_amount_cents: 700, precise_coupons_amount_cents: coupon2)
  end

  describe ".build" do
    subject(:line_items) { described_class.build(fees) }

    let(:other_fee) { build_stubbed(:charge_fee, invoice:) }
    let(:add_on_fee) { build_stubbed(:add_on_fee, invoice:) }
    let(:fees) { [fee1, add_on_fee, fee2, other_fee] }

    it "groups by charge, preserving order and unrelated fees" do
      expect(line_items.map(&:item_key)).to eq([charge.id, add_on_fee.item_key, other_fee.item_key])
      expect(line_items.first.fees).to eq([fee1, fee2])
      expect(line_items.drop(1)).to eq([add_on_fee, other_fee])
    end

    context "when the same charge belongs to another subscription" do
      let(:other_fee) { build_stubbed(:charge_fee, invoice:, charge:, amount_cents: 400) }
      let(:fees) { [fee1, fee2, other_fee] }

      it "includes all subscriptions in one charge line" do
        expect(line_items.sole.fees).to eq(fees)
        expect(line_items.sole.amount_cents).to eq(1400)
      end
    end
  end

  describe "the payload interface" do
    let(:charge) { create(:standard_charge) }

    it "sums amounts and units, using the charge identity" do
      expect(group).to have_attributes(
        id: nil, item_key: charge.id, item_id: charge.id, charge?: true,
        billable_metric: charge.billable_metric, units: 5, amount_cents: 1000,
        sub_total_excluding_taxes_amount_cents: 1000
      )
    end

    context "when a fee carries a coupon" do
      let(:coupon2) { 200 }

      it { expect(group.sub_total_excluding_taxes_amount_cents).to eq(800) }
    end
  end

  describe "#split_taxes" do
    subject(:fee_taxes) { group.split_taxes(group_taxes) }

    let(:tax_amount) { 100 }
    let(:group_taxes) do
      build(:tax_result, item_code: "metric_code", tax_amount_cents: tax_amount, tax_breakdown: [
        build(:tax_breakdown_item, name: "VAT", type: "tax", rate: "0.10", tax_amount:)
      ])
    end

    it "returns proportional fee results and preserves jurisdiction metadata" do
      expect(fee_taxes.map(&:item_key)).to eq([fee1.item_key, fee2.item_key])
      expect(fee_taxes.map(&:item_id)).to eq([fee1.id, fee2.id])
      expect(fee_taxes.map(&:item_code)).to eq(%w[metric_code metric_code])
      expect(fee_taxes.map(&:amount_cents)).to eq([300, 700])
      expect(fee_taxes.map(&:tax_amount_cents)).to eq([30, 70])
      expect(fee_taxes.map { |item| item.tax_breakdown.sole }).to all(
        have_attributes(name: "VAT", type: "tax", rate: "0.10")
      )
    end

    context "when a jurisdiction amount does not divide over the fees" do
      let(:tax_amount) { 7 }

      it "allocates whole cents without losing the unrounded shares" do
        expect(fee_taxes.map { |item| item.tax_breakdown.sole.allocated_amount_cents }).to eq([2, 5])
        expect(fee_taxes.map { |item| item.tax_breakdown.sole.tax_amount }).to eq([2.1.to_d, 4.9.to_d])
      end
    end

    context "when fractional jurisdiction amounts round differently from their total" do
      let(:group_taxes) do
        build(:tax_result, tax_amount_cents: 8, tax_breakdown: %w[State County City].map do |name|
          build(:tax_breakdown_item, name:, type: "tax", rate: "0.025", tax_amount: 2.5)
        end)
      end

      it "reconciles jurisdiction totals while preserving the precise shares" do
        expect(fee_taxes.map(&:tax_amount_cents)).to eq([3, 5])
        amounts = fee_taxes.flat_map(&:tax_breakdown).group_by(&:name)
          .transform_values { |taxes| taxes.sum(&:allocated_amount_cents) }
        expect(amounts).to eq("State" => 3, "County" => 3, "City" => 2)
        expect(fee_taxes.map { |item| item.tax_breakdown.sum(&:tax_amount) }).to eq([2.25.to_d, 5.25.to_d])
      end
    end

    context "when the provider taxed less than the full rate" do
      let(:tax_amount) { 80 }

      it "preserves the reduced taxable proportion" do
        expect(fee_taxes.map { |item| item.tax_breakdown.sole.tax_amount }).to eq([24, 56])
      end
    end

    context "when the breakdown carries a special taxation type" do
      let(:group_taxes) do
        build(:tax_result, tax_amount_cents: 0, tax_breakdown: [
          build(:tax_breakdown_item, name: "Reverse charge", type: "exempt", rate: "0.00", tax_amount: 0)
        ])
      end

      it "splits without dividing by the rate" do
        expect(fee_taxes.map { |item| item.tax_breakdown.sole.tax_amount }).to eq([0, 0])
        expect(fee_taxes.map(&:tax_amount_cents)).to eq([0, 0])
      end
    end

    context "when the provider returns no tax breakdown" do
      let(:group_taxes) { build(:tax_result, tax_amount_cents: 0, tax_breakdown: []) }

      it "keeps a zero-tax result for every fee" do
        expect(fee_taxes.map(&:item_id)).to eq([fee1.id, fee2.id])
        expect(fee_taxes.map(&:tax_breakdown)).to eq([[], []])
        expect(fee_taxes.map(&:tax_amount_cents)).to eq([0, 0])
      end
    end

    context "when coupons cancel the whole group amount" do
      let(:coupon1) { 300 }
      let(:coupon2) { 700 }

      it { expect(fee_taxes.map(&:tax_amount_cents)).to eq([0, 0]) }
    end
  end
end
