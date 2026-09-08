# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Taxes::Invoices::ChargeFeeGroup do
  subject(:group) { described_class.new(charge_id: charge.id, fees: [fee1, fee2]) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, organization:, plan:, billable_metric:) }
  let(:other_charge) { create(:standard_charge, organization:, plan:, billable_metric:) }

  let(:fee1) do
    create(:charge_fee, invoice:, charge:, units: 2, amount_cents: 300, precise_amount_cents: 300)
  end
  let(:fee2) do
    create(:charge_fee, invoice:, charge:, units: 3, amount_cents: 700, precise_amount_cents: 700)
  end

  describe ".build" do
    let(:other_fee) { create(:charge_fee, invoice:, charge: other_charge, amount_cents: 100) }
    let(:add_on_fee) { create(:add_on_fee, invoice:, amount_cents: 100) }

    it "groups the fees of a charge that has several of them" do
      line_items = described_class.build([fee1, other_fee, fee2])

      expect(line_items.map(&:item_key)).to eq(["charge_#{charge.id}", other_fee.item_key])
      expect(line_items.first.fees).to eq([fee1, fee2])
    end

    it "leaves a charge with a single fee and non-charge fees on their own" do
      line_items = described_class.build([add_on_fee, other_fee])

      expect(line_items).to eq([add_on_fee, other_fee])
    end

    it "groups the fees of a charge billed for two subscriptions of the same plan" do
      other_subscription_fee = create(
        :charge_fee,
        invoice:,
        charge:,
        subscription: create(:subscription, customer:, plan:),
        amount_cents: 400
      )

      line_items = described_class.build([fee1, fee2, other_subscription_fee])

      expect(line_items.sole.fees).to eq([fee1, fee2, other_subscription_fee])
      expect(line_items.sole.amount_cents).to eq(1400)
    end

    it "keeps every line item at the position of its first fee" do
      line_items = described_class.build([fee1, add_on_fee, fee2, other_fee])

      expect(line_items.map(&:item_key))
        .to eq(["charge_#{charge.id}", add_on_fee.item_key, other_fee.item_key])
    end
  end

  describe "the payload interface" do
    it "sums the amounts and units of its fees" do
      expect(group).to have_attributes(
        item_key: "charge_#{charge.id}",
        item_id: "charge_#{charge.id}",
        charge?: true,
        billable_metric:,
        units: 5,
        amount_cents: 1000,
        sub_total_excluding_taxes_amount_cents: 1000
      )
    end

    context "when a fee carries a coupon" do
      let(:fee2) do
        create(
          :charge_fee,
          invoice:,
          charge:,
          units: 3,
          amount_cents: 700,
          precise_amount_cents: 700,
          precise_coupons_amount_cents: 200
        )
      end

      it "excludes the coupon from the taxable amount" do
        expect(group.sub_total_excluding_taxes_amount_cents).to eq(800)
      end
    end
  end

  describe "#split_taxes" do
    subject(:fee_taxes) { group.split_taxes(group_taxes) }

    let(:group_taxes) do
      build(
        :tax_result,
        item_key: "charge_#{charge.id}",
        item_id: "charge_#{charge.id}",
        item_code: "metric_code",
        amount_cents: 1000,
        tax_amount_cents: 100,
        tax_breakdown: [build(:tax_breakdown_item, name: "VAT", type: "tax", rate: "0.10", tax_amount: 100)]
      )
    end

    it "returns one result per fee, identified by the fee" do
      expect(fee_taxes.map(&:item_key)).to eq([fee1.item_key, fee2.item_key])
      expect(fee_taxes.map(&:item_id)).to eq([fee1.id, fee2.id])
      expect(fee_taxes.map(&:item_code)).to eq(%w[metric_code metric_code])
    end

    it "carries the group identity and its tax amount on every result" do
      expect(fee_taxes.map(&:group_key)).to eq(["charge_#{charge.id}", "charge_#{charge.id}"])
      expect(fee_taxes.map(&:group_tax_amount_cents)).to eq([100, 100])
    end

    it "splits the amounts proportionally to each fee sub-total" do
      expect(fee_taxes.map(&:amount_cents)).to eq([300, 700])
      expect(fee_taxes.map(&:tax_amount_cents)).to eq([30, 70])
      expect(fee_taxes.map { |item| item.tax_breakdown.sole.tax_amount }).to eq([30, 70])
    end

    it "allocates whole cents of each jurisdiction amount to every fee" do
      expect(fee_taxes.map { |item| item.tax_breakdown.sole.allocated_amount_cents }).to eq([30, 70])
    end

    context "when a jurisdiction amount does not divide over the fees" do
      let(:group_taxes) do
        build(
          :tax_result,
          item_id: "charge_#{charge.id}",
          tax_amount_cents: 7,
          tax_breakdown: [build(:tax_breakdown_item, name: "VAT", type: "tax", rate: "0.10", tax_amount: 7)]
        )
      end

      it "gives the odd cent to the fee with the largest remainder" do
        allocated = fee_taxes.map { |item| item.tax_breakdown.sole.allocated_amount_cents }

        expect(allocated).to eq([2, 5])
        expect(allocated.sum).to eq(7)
      end
    end

    it "keeps the rate of every breakdown item" do
      expect(fee_taxes.map { |item| item.tax_breakdown.sole }).to all(
        have_attributes(name: "VAT", type: "tax", rate: "0.10")
      )
    end

    context "when the provider taxed less than the full rate" do
      let(:group_taxes) do
        build(
          :tax_result,
          item_id: "charge_#{charge.id}",
          tax_amount_cents: 80,
          tax_breakdown: [build(:tax_breakdown_item, name: "VAT", type: "tax", rate: "0.10", tax_amount: 80)]
        )
      end

      it "keeps the group ratio on each fee so the taxable base rate is preserved" do
        breakdown_amounts = fee_taxes.map { |item| item.tax_breakdown.sole.tax_amount }

        expect(breakdown_amounts).to eq([24, 56])
        expect(breakdown_amounts.sum).to eq(80)
      end

      it "allocates the reduced amount over the fees" do
        expect(fee_taxes.map { |item| item.tax_breakdown.sole.allocated_amount_cents }).to eq([24, 56])
      end
    end

    context "when the breakdown carries a special taxation type" do
      let(:group_taxes) do
        build(
          :tax_result,
          item_id: "charge_#{charge.id}",
          tax_amount_cents: 0,
          tax_breakdown: [build(:tax_breakdown_item, name: "Reverse charge", type: "exempt", rate: "0.00", tax_amount: 0)]
        )
      end

      it "splits without dividing by the rate" do
        expect(fee_taxes.map { |item| item.tax_breakdown.sole.tax_amount }).to eq([0, 0])
        expect(fee_taxes.map(&:tax_amount_cents)).to eq([0, 0])
      end
    end

    context "when coupons cancel the whole group amount" do
      let(:fee1) do
        create(
          :charge_fee,
          invoice:,
          charge:,
          amount_cents: 300,
          precise_amount_cents: 300,
          precise_coupons_amount_cents: 300
        )
      end
      let(:fee2) do
        create(
          :charge_fee,
          invoice:,
          charge:,
          amount_cents: 700,
          precise_amount_cents: 700,
          precise_coupons_amount_cents: 700
        )
      end

      it "splits without dividing by zero" do
        expect(fee_taxes.map(&:tax_amount_cents)).to eq([0, 0])
      end
    end
  end
end
