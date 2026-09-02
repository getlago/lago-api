# frozen_string_literal: true

require "rails_helper"

# Every expected amount below is taken from fixed-charge-pay-in-advance.md.
#
#   May 2025, 31 days. Standard $31.00/unit/period.
#   Tiered: units 0-5 -> $31.00/unit + $10.00 flat, units 6+ -> $62.00/unit + $10.00 flat.
RSpec.describe BillingCycles::Fees::AdvanceDeltaService do
  subject(:result) do
    described_class.call(billing_cycle:, units:, already_billed_units:)
  end

  let(:organization) { create(:organization, timezone: "UTC") }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD") }

  let(:rate_card_rate) do
    create(:rate_card_rate, organization:, rate_card:, rate_model:, rate_properties:)
  end

  let(:subscription_rate_card) do
    create(:subscription_rate_card, organization:, subscription:, customer:, rate_card:)
  end

  # The window still ahead of the change. proration_ratio is its share of the period.
  let(:billing_cycle) do
    create(
      :billing_cycle,
      organization:,
      subscription:,
      customer:,
      subscription_rate_card:,
      rate_card_rate:,
      rate_properties:,
      proration_ratio:,
      period_from: Time.utc(2025, 5, 1),
      period_to: Time.utc(2025, 5, 31).end_of_day
    )
  end

  let(:tiered_ranges) do
    [
      {"from_value" => 0, "to_value" => 5, "per_unit_amount" => "31", "flat_amount" => "10"},
      {"from_value" => 6, "to_value" => nil, "per_unit_amount" => "62", "flat_amount" => "10"}
    ]
  end

  def amount_cents
    (result.amount * 100).round
  end

  describe "standard, prorated" do
    let(:rate_model) { "standard" }
    let(:rate_properties) { {"amount" => "31"} }

    context "with the May 02 increase: 1 -> 3, 30 days remaining" do
      let(:proration_ratio) { BigDecimal(30) / 31 }
      let(:units) { 3 }
      let(:already_billed_units) { 1 }

      it "bills $60.00 for 2 units" do
        expect(result.billable_units).to eq(2)
        expect(amount_cents).to eq(6_000)
      end
    end

    context "with the May 03 increase: 3 -> 5, 29 days remaining" do
      let(:proration_ratio) { BigDecimal(29) / 31 }
      let(:units) { 5 }
      let(:already_billed_units) { 3 }

      it "bills $58.00 for 2 units" do
        expect(result.billable_units).to eq(2)
        expect(amount_cents).to eq(5_800)
      end
    end

    context "with the May 04 decrease: 5 -> 1" do
      let(:proration_ratio) { BigDecimal(28) / 31 }
      let(:units) { 1 }
      let(:already_billed_units) { 5 }

      it "bills nothing and never refunds" do
        expect(result.billable_units).to eq(0)
        expect(amount_cents).to eq(0)
      end
    end

    context "with the May 05 increase below the watermark: 1 -> 2, watermark 5" do
      let(:proration_ratio) { BigDecimal(27) / 31 }
      let(:units) { 2 }
      let(:already_billed_units) { 5 }

      it "bills nothing until the quantity exceeds the watermark" do
        expect(result.billable_units).to eq(0)
        expect(amount_cents).to eq(0)
      end
    end
  end

  describe "standard, not prorated" do
    let(:rate_model) { "standard" }
    let(:rate_properties) { {"amount" => "31"} }
    let(:proration_ratio) { 1 }

    context "with the May 02 increase: 1 -> 3" do
      let(:units) { 3 }
      let(:already_billed_units) { 1 }

      it "bills $62.00 at the full period price" do
        expect(amount_cents).to eq(6_200)
      end
    end

    context "with the May 03 increase: 3 -> 5" do
      let(:units) { 5 }
      let(:already_billed_units) { 3 }

      it "bills $62.00 at the full period price" do
        expect(amount_cents).to eq(6_200)
      end
    end
  end

  # Graduated only ever reaches this service with ratio 1, since graduated + advance +
  # proration is rejected at configuration time.
  describe "graduated, not prorated" do
    let(:rate_model) { "graduated" }
    let(:rate_properties) { {"graduated_ranges" => tiered_ranges} }
    let(:proration_ratio) { 1 }

    context "with the May 02 increase: 1 -> 3, both inside tier 1" do
      let(:units) { 3 }
      let(:already_billed_units) { 1 }

      it "bills $62.00 and does not re-charge the tier 1 flat fee" do
        expect(amount_cents).to eq(6_200)
      end
    end

    # The case the legacy engine gets wrong: it bills $134.00 by pricing 4 units from
    # position 1. Units 6-7 belong in tier 2.
    context "with the May 03 increase: 3 -> 7, crossing into tier 2" do
      let(:units) { 7 }
      let(:already_billed_units) { 3 }

      it "bills $196.00, pricing units 6-7 in tier 2 plus its flat fee" do
        expect(result.billable_units).to eq(4)
        expect(amount_cents).to eq(19_600)
      end
    end

    context "with the May 06 increase: 7 -> 8, already inside tier 2" do
      let(:units) { 8 }
      let(:already_billed_units) { 7 }

      it "bills $62.00 at the tier 2 rate with no further flat fee" do
        expect(result.billable_units).to eq(1)
        expect(amount_cents).to eq(6_200)
      end
    end

    context "with the May 07 decrease: 8 -> 4" do
      let(:units) { 4 }
      let(:already_billed_units) { 8 }

      it "bills nothing" do
        expect(amount_cents).to eq(0)
      end
    end
  end
end
