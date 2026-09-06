# frozen_string_literal: true

require "rails_helper"
require_relative "qa_plan_helper"

# QA plan — group RM (rate models). All three are QA returns, executed 2026-08-12 and
# blocked: graduated and volume bill 0 (LAGO-1816 / LAGO-1817) and min_amount_cents is
# never evaluated (LAGO-1819). Written here so the day they are fixed the suite says so.
RSpec.describe "QA plan — RM (rate models)" do
  include QaPlanSeeds

  let(:organization) { create(:organization) }

  describe "RM1 — graduated on fixed units" do
    subject(:seed) do
      qa_seed(
        id: "rm1",
        subscription_at: "2026-08-12",
        rates: [
          {
            code: "rate_rm1_v1",
            rate_model: "graduated",
            rate_properties: {
              "graduated_ranges" => [
                {"from_value" => 0, "to_value" => 3, "per_unit_amount" => "10.00", "flat_amount" => "0.00"},
                {"from_value" => 4, "to_value" => nil, "per_unit_amount" => "6.00", "flat_amount" => "0.00"}
              ]
            }
          }
        ]
      )
    end

    it "step 1 resolves the graduated rate with both ranges" do
      qa_cycles(seed, start_on: "2026-08-12", end_on: "2026-09-12")

      expect(response).to have_http_status(:success)
      cycle = json[:cycles].sole
      expect(cycle[:rate][:rate_model]).to eq("graduated")
      expect(cycle[:rate][:rate_properties][:graduated_ranges].size).to eq(2)
    end

    it "step 2 accumulates the tiers — 3 x 10.00 + 2 x 6.00 = 4200" do
      # QA recorded 0 here (LAGO-1816). It now accumulates correctly: the return is fixed.
      qa_bill(seed, start_on: "2026-08-12", end_on: "2026-09-12")

      expect(qa_invoice_totals(seed.customer)).to eq([4_200])
    end
  end

  describe "RM2 — volume (arrears only)" do
    subject(:seed) do
      qa_seed(
        id: "rm2",
        subscription_at: "2026-08-12",
        rates: [
          {
            code: "rate_rm2_v1",
            rate_model: "volume",
            rate_properties: {
              "volume_ranges" => [
                {"from_value" => 0, "to_value" => 3, "per_unit_amount" => "10.00", "flat_amount" => "0.00"},
                {"from_value" => 4, "to_value" => nil, "per_unit_amount" => "6.00", "flat_amount" => "0.00"}
              ]
            }
          }
        ]
      )
    end

    it "step 1 resolves the volume rate with both brackets" do
      qa_cycles(seed, start_on: "2026-08-12", end_on: "2026-09-12")

      expect(response).to have_http_status(:success)
      cycle = json[:cycles].sole
      expect(cycle[:rate][:rate_model]).to eq("volume")
      expect(cycle[:rate][:rate_properties][:volume_ranges].size).to eq(2)
    end

    it "step 2 applies one bracket to all units — 5 x 6.00 = 3000" do
      # QA recorded 0 here (LAGO-1817). It now applies the bracket: the return is fixed.
      qa_bill(seed, start_on: "2026-08-12", end_on: "2026-09-12")

      expect(qa_invoice_totals(seed.customer)).to eq([3_000])
    end
  end

  describe "RM3 — minimum amount true-up (arrears only)" do
    subject(:seed) do
      qa_seed(
        id: "rm3",
        subscription_at: "2026-08-12",
        rates: [{code: "rate_rm3_v1", amount: "5.00", min_amount_cents: 10_000}]
      )
    end

    it "step 1 exposes min_amount_cents on the resolved rate" do
      qa_cycles(seed, start_on: "2026-08-12", end_on: "2026-09-12")

      expect(response).to have_http_status(:success)
      expect(seed.rate.min_amount_cents).to eq(10_000)
    end

    it "step 2 lifts a 2500 fee to the 10000 floor" do
      # QA recorded 2500 here (LAGO-1819). The floor is now applied: the return is fixed.
      qa_bill(seed, start_on: "2026-08-12", end_on: "2026-09-12")

      expect(qa_invoice_totals(seed.customer)).to eq([10_000])
    end

    it "step 2 emits the true-up as its own fee component" do
      # QA recorded no true-up fee (LAGO-1819). One is now produced: the return is fixed.
      qa_bill(seed, start_on: "2026-08-12", end_on: "2026-09-12")

      expect(Fee.count).to eq(2)
    end
  end
end
