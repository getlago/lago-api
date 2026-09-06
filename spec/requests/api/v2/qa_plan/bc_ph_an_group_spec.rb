# frozen_string_literal: true

require "rails_helper"
require_relative "qa_plan_helper"

# QA plan — groups BC (cycle matrix), PH (rate phases) and AN (anchor x proration).
RSpec.describe "QA plan — BC / PH / AN" do
  include QaPlanSeeds

  let(:organization) { create(:organization) }

  describe "BC — cycle matrix, all units x counts" do
    QaPlanSeeds::BC_MATRIX.each do |label, count, unit, first_period, second_period, first_invoice_date|
      context "#{label} — #{unit} x #{count}" do
        # The plan bills the window [started_at -> period-2 boundary]; in arrears the
        # boundary that closes period 2 is the day after its last covered day.
        let(:window_end) { (Date.parse(second_period.last) + 1).to_s }

        subject(:seed) do
          qa_seed(
            id: label.downcase,
            rates: [{code: "rate_#{label.downcase}_v1", interval_count: count, interval_unit: unit}]
          )
        end

        it "step 1 places both period boundaries exactly" do
          qa_cycles(seed, start_on: "2026-08-10", end_on: window_end)

          expect(response).to have_http_status(:success)
          expect(json[:cycles].first(2).map { [it[:period_from][0, 10], it[:period_to][0, 10]] })
            .to eq([first_period, second_period])
        end

        # The global assertion of the group: a non-prorated fixed fee never scales with
        # period length. One day and two years both bill 150.00.
        it "step 2 bills 15000 per period regardless of length" do
          qa_bill(seed, start_on: "2026-08-10", end_on: window_end)

          expect(response).to have_http_status(:success)
          expect(qa_invoice_totals(seed.customer).first(2)).to eq([15_000, 15_000])
        end

        # The plan's BC table dates the first invoice the day after period 1 closes, which
        # is the arrears convention its Conventions page states ("the day after period end
        # (= next boundary)"). Its Standard-assertions page states the opposite — see
        # QA_ACCEPTANCE.md, the issuing_date break.
        it "issues the first invoice on #{first_invoice_date}" do
          qa_bill(seed, start_on: "2026-08-10", end_on: window_end)

          expect(qa_issuing_dates(seed.customer).first).to eq(first_invoice_date)
        end
      end
    end
  end

  describe "PH1 — trial phase ($0 for 14 days, then standard)" do
    subject(:seed) do
      qa_seed(
        id: "ph1",
        phases: [
          {
            code: "trial", position: 1, cycle_count: 1,
            override: {amount: "0.00", interval_count: 14, interval_unit: "day"}
          },
          {code: "std", position: 2, cycle_count: nil}
        ]
      )
    end

    it "step 1 shows a 14-day trial cycle then a monthly standard cycle" do
      qa_cycles(seed, start_on: "2026-08-10", end_on: "2026-09-24")

      expect(response).to have_http_status(:success)
      expect(json[:cycles].map { it[:rate_phase_code] }).to eq(%w[trial std])
      expect(json[:cycles].map { [it[:period_from][0, 10], it[:period_to][0, 10]] }).to eq(
        [%w[2026-08-10 2026-08-23], %w[2026-08-24 2026-09-23]]
      )
    end

    it "step 2 bills 0 for the trial and 15000 for the standard period" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-24")

      expect(response).to have_http_status(:success)
      expect(qa_invoice_totals(seed.customer)).to eq([0, 15_000])
    end
  end

  describe "PH2 — three phases: trial → intro → standard" do
    subject(:seed) do
      qa_seed(
        id: "ph2",
        phases: [
          {
            code: "trial", position: 1, cycle_count: 1,
            override: {amount: "0.00", interval_count: 14, interval_unit: "day"}
          },
          {code: "intro", position: 2, cycle_count: 3, override: {amount: "15.00"}},
          {code: "std", position: 3, cycle_count: nil}
        ]
      )
    end

    it "step 1 shows five cycles — trial x1, intro x3, std x1" do
      qa_cycles(seed, start_on: "2026-08-10", end_on: "2026-12-24")

      expect(response).to have_http_status(:success)
      expect(json[:cycles].map { it[:rate_phase_code] }).to eq(%w[trial intro intro intro std])
    end

    it "step 2 bills 0 · 7500 · 7500 · 7500 · 15000" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-12-24")

      expect(response).to have_http_status(:success)
      expect(qa_invoice_totals(seed.customer)).to eq([0, 7_500, 7_500, 7_500, 15_000])
    end

    it "transitions at boundaries only — exactly three intro cycles" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-12-24")

      expect(Fee.where(amount_cents: 7_500).count).to eq(3)
    end
  end

  describe "PH3 — cadence switch between phases (monthly → yearly)" do
    subject(:seed) do
      qa_seed(
        id: "ph3",
        phases: [
          {code: "monthly_start", position: 1, cycle_count: 3},
          {
            code: "yearly_tail", position: 2, cycle_count: nil,
            override: {amount: "300.00", interval_count: 1, interval_unit: "year"}
          }
        ]
      )
    end

    it "step 1 shows three monthly cycles then one yearly tail" do
      qa_cycles(seed, start_on: "2026-08-10", end_on: "2027-11-10")

      expect(response).to have_http_status(:success)
      expect(json[:cycles].map { it[:rate_phase_code] })
        .to eq(%w[monthly_start monthly_start monthly_start yearly_tail])
      expect(json[:cycles].last[:period_from][0, 10]).to eq("2026-11-10")
      expect(json[:cycles].last[:period_to][0, 10]).to eq("2027-11-09")
    end

    it "step 2 bills 15000 x3 then 150000" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2027-11-10")

      expect(response).to have_http_status(:success)
      expect(qa_invoice_totals(seed.customer)).to eq([15_000, 15_000, 15_000, 150_000])
    end
  end

  describe "PH4 — default tail re-resolves the card's newest rate" do
    subject(:seed) do
      qa_seed(
        id: "ph4",
        rates: [
          {code: "rate_ph4_v1", effective_from: "2026-01-01", amount: "30.00"},
          {code: "rate_ph4_v2", effective_from: "2026-10-10", amount: "36.00"}
        ],
        phases: [{code: "std", position: 1, cycle_count: nil}]
      )
    end

    it "follows the card's rate timeline under a locked plan" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-11-10")

      expect(response).to have_http_status(:success)
      expect(qa_invoice_totals(seed.customer)).to eq([15_000, 15_000, 18_000])
    end
  end

  describe "AN1 — prorated stub (proration: true)" do
    subject(:seed) do
      qa_seed(id: "an1", proration: true, subscription_at: "2026-08-20", anchor: "2026-09-01")
    end

    it "step 1 shows the stub then the anchored period" do
      qa_cycles(seed, start_on: "2026-08-20", end_on: "2026-10-01")

      expect(response).to have_http_status(:success)
      expect(json[:cycles].map { [it[:period_from][0, 10], it[:period_to][0, 10]] }).to eq(
        [%w[2026-08-20 2026-08-31], %w[2026-09-01 2026-09-30]]
      )
    end

    # 150 x 12/31 = 58.06 (half-up to the cent, settled 2026-08-10).
    it "step 2 prorates the stub to 5806 and bills the anchored period in full" do
      qa_bill(seed, start_on: "2026-08-20", end_on: "2026-10-01")

      expect(response).to have_http_status(:success)
      expect(qa_invoice_totals(seed.customer)).to eq([5_806, 15_000])
    end
  end

  describe "AN2 — full-fee stub (proration: false)" do
    subject(:seed) do
      qa_seed(id: "an2", subscription_at: "2026-08-20", anchor: "2026-09-01")
    end

    it "step 1 shows the same two cycles as AN1" do
      qa_cycles(seed, start_on: "2026-08-20", end_on: "2026-10-01")

      expect(response).to have_http_status(:success)
      expect(json[:cycles].map { [it[:period_from][0, 10], it[:period_to][0, 10]] }).to eq(
        [%w[2026-08-20 2026-08-31], %w[2026-09-01 2026-09-30]]
      )
    end

    it "step 2 charges the stub in full — 15000, not prorated, not skipped" do
      qa_bill(seed, start_on: "2026-08-20", end_on: "2026-10-01")

      expect(response).to have_http_status(:success)
      expect(qa_invoice_totals(seed.customer)).to eq([15_000, 15_000])
    end
  end
end
