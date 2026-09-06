# frozen_string_literal: true

require "rails_helper"
require_relative "qa_plan_helper"

# QA plan — group R (rate lifecycle). R1, R2 and R3 are QA-approved (2026-08-10); the
# amounts and boundaries asserted here are the values QA recorded live on staging.
RSpec.describe "QA plan — R (rate lifecycle)" do
  include QaPlanSeeds

  let(:organization) { create(:organization) }

  describe "R1 — invoicing at the active rate" do
    subject(:seed) do
      qa_seed(
        id: "r1",
        rates: [
          {code: "rate_r1_v1", effective_from: "2026-01-01", amount: "30.00"},
          {code: "rate_r1_v2", effective_from: "2026-12-01", amount: "40.00"}
        ]
      )
    end

    it "step 1 previews exactly one cycle on the active rate" do
      qa_cycles(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect(response).to have_http_status(:success)
      cycle = json[:cycles].sole
      expect(cycle[:rate_code]).to eq("rate_r1_v1")
      expect(cycle[:rate_phase_code]).to eq("default")
      expect(cycle[:period_from]).to eq("2026-08-10T00:00:00Z")
      expect(cycle[:period_to]).to eq("2026-09-09T23:59:59Z")
      # QA recorded `billing_at == period_to` (2026-09-09T23:59:59Z). The engine now
      # publishes the half-open exclusive end here; only `period_to` is converted back.
      expect(cycle[:billing_at]).to eq("2026-09-09T23:59:59Z")
    end

    it "step 1 creates no invoice" do
      seed

      expect { qa_cycles(seed, start_on: "2026-08-10", end_on: "2026-09-10") }
        .not_to change(Invoice, :count)
    end

    it "step 2 bills exactly one invoice of 15000 cents at the active rate" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect(response).to have_http_status(:success)
      expect(qa_invoice_totals(seed.customer)).to eq([15_000])
      expect(Fee.sole.rate_card_rate.code).to eq("rate_r1_v1")
      expect(qa_issuing_dates(seed.customer)).to eq(["2026-09-09"])
    end

    it "step 2 pins the fee boundaries QA recorded" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      fee = Fee.sole
      expect(fee.properties["from_datetime"]).to start_with("2026-08-10T00:00:00")
      expect(fee.properties["to_datetime"]).to start_with("2026-09-09T23:59:59")
    end

    it "step 2 is idempotent — the same window rerun creates no duplicate" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")
      expect(Invoice.count).to eq(1)

      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect(Invoice.count).to eq(1)
      expect(qa_invoice_totals(seed.customer)).to eq([15_000])
    end
  end

  describe "R2 — no active rate at billing time" do
    subject(:seed) do
      qa_seed(id: "r2", rates: [{code: "rate_r2_v1", effective_from: "2027-01-01", amount: "30.00"}])
    end

    it "step 1 returns an empty cycles list with a next billing date" do
      qa_cycles(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect(response).to have_http_status(:success)
      expect(json[:cycles]).to eq([])
      # QA recorded next_billing_at "2026-10-10" here and filed it as a known return
      # (LAGO-1792): a next boundary reported while nothing is priced. The key is now
      # omitted, which is what LAGO-1792 asked for.
      expect(json).not_to have_key(:next_billing_at)
    end

    it "step 2 creates no document at all — not even a zero-amount invoice" do
      seed

      expect { qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10") }
        .not_to change(Invoice, :count)

      expect(response).to have_http_status(:success)
      expect(json[:invoices]).to eq([])
      expect(Invoice.count).to eq(0)
      expect(Fee.count).to eq(0)
    end

    it "bills 1:1 once the window reaches the priced periods" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2027-02-10")

      expect(response).to have_http_status(:success)
      expect(Invoice.count).to eq(2)
    end
  end

  describe "R3a — rate change ON a boundary" do
    subject(:seed) do
      qa_seed(
        id: "r3a",
        rates: [
          {code: "rate_r3a_v1", effective_from: "2026-01-01", amount: "30.00"},
          {code: "rate_r3a_v2", effective_from: "2026-10-10", amount: "36.00"}
        ]
      )
    end

    it "step 1 shows the switch as three whole cycles, no split" do
      qa_cycles(seed, start_on: "2026-08-10", end_on: "2026-11-10")

      expect(response).to have_http_status(:success)
      expect(json[:cycles].map { it[:rate_code] })
        .to eq(%w[rate_r3a_v1 rate_r3a_v1 rate_r3a_v2])
      expect(json[:cycles].map { it[:period_from] }).to eq(
        ["2026-08-10T00:00:00Z", "2026-09-10T00:00:00Z", "2026-10-10T00:00:00Z"]
      )
    end

    it "step 2 bills three invoices — 15000 · 15000 · 18000" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-11-10")

      expect(response).to have_http_status(:success)
      expect(qa_invoice_totals(seed.customer)).to eq([15_000, 15_000, 18_000])
    end

    it "issues no document from the activation datetime itself" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-11-10")

      expect(Invoice.count).to eq(3)
      expect(BillingCycle.count).to eq(3)
    end
  end

  describe "R3b — rate change MID-period (closing invoice)" do
    subject(:seed) do
      qa_seed(
        id: "r3b",
        proration: true,
        rates: [
          {code: "rate_r3b_v1", effective_from: "2026-01-01", amount: "30.00"},
          {code: "rate_r3b_v2", effective_from: "2026-09-25", amount: "36.00"}
        ]
      )
    end

    it "step 1 exposes the split as two entries sharing one cycle index" do
      qa_cycles(seed, start_on: "2026-08-10", end_on: "2026-10-10")

      expect(response).to have_http_status(:success)
      split = json[:cycles].select { it[:period_from] < "2026-10-10" }.group_by { it[:cycle_index] }
      expect(split.values.map(&:size)).to include(2)
      cut = split.values.find { it.size == 2 }
      expect(cut.map { it[:rate_code] }).to eq(%w[rate_r3b_v1 rate_r3b_v2])
      expect(cut.first[:period_from]).to eq("2026-09-10T00:00:00Z")
      expect(cut.first[:period_to]).to eq("2026-09-24T23:59:59Z")
      expect(cut.last[:period_from]).to eq("2026-09-25T00:00:00Z")
      expect(cut.last[:period_to]).to eq("2026-10-09T23:59:59Z")
    end

    # The measurement that matters most: QA pinned "one separate document per transition".
    it "step 2 bills four invoices — 15000 · 7500 · 9000 · 18000" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-11-10")

      expect(response).to have_http_status(:success)
      expect(qa_invoice_totals(seed.customer)).to eq([15_000, 7_500, 9_000, 18_000])
    end

    it "step 2 prorates at the unit-price level — 15.0 on the closing slice, 18.0 after" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-11-10")

      closing = Fee.find_by(amount_cents: 7_500)
      reopened = Fee.find_by(amount_cents: 9_000)
      expect(closing.precise_unit_amount).to eq(15.0)
      expect(reopened.precise_unit_amount).to eq(18.0)
    end

    # QA pinned "one separate document per transition". That holds only while each slice
    # keeps its own billing instant; a clamp collapsing overdue slices onto "now" would
    # merge all four onto one invoice. The stored instants are the half-open exclusive
    # ends, one boundary later in presentation than the inclusive ends QA read off /cycles.
    it "step 2 gives each transition slice its own billing instant" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-11-10")

      expect(qa_cycle_rows.map { it[:billing_at] }).to eq(
        [
          "2026-09-10T00:00:00Z",
          "2026-09-25T00:00:00Z",
          "2026-10-10T00:00:00Z",
          "2026-11-10T00:00:00Z"
        ]
      )
    end
  end
end
