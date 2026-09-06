# frozen_string_literal: true

require "rails_helper"
require_relative "qa_plan_helper"

# QA plan — group X (additional coverage). X2 (advance termination) is OPEN in the plan
# (OQ #5) and X10/X11 are reference-only, so neither is executed here.
RSpec.describe "QA plan — X (additional coverage)" do
  include QaPlanSeeds

  let(:organization) { create(:organization) }

  def qa_terminate(seed, at:)
    travel_to(Time.zone.parse("#{at} 12:00:00")) do
      delete_with_token(
        organization,
        "/api/v2/subscriptions/#{seed.external_id}",
        {terminated_at: "#{at}T00:00:00Z"}
      )
    end
  end

  # The plan drives termination through `POST /bill` with `terminate: true` (contract C4).
  # That parameter does not exist on this controller, and once DELETE has terminated the
  # subscription /bill answers 404 — so the final cycle is asserted on the durable record
  # the termination writes, which is what the clock then invoices.
  describe "X1 — termination, arrears" do
    context "with proration: true" do
      subject(:seed) { qa_seed(id: "x1p", proration: true) }

      before do
        qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")
        qa_terminate(seed, at: "2026-09-25")
      end

      it "terminates through the endpoint" do
        expect(response).to have_http_status(:success)
      end

      # The termination day is INCLUSIVE — decided by the product owner on 2026-09-05, which
      # is the convention the plan asked to have pinned ("If actual = 75.00 (15 d), the
      # termination day is exclusive — record, pin the convention"). A day entered is a day
      # paid for, so Sep 10 -> Sep 25 is 16 days of 30 and the final fee is 80.00.
      #
      # An earlier agent pinned the opposite here, on the strength of what the code did at
      # the time. That was reading a decision off an implementation; the plan had deliberately
      # deferred it, and its own written expectation was the 16-day one all along.
      it "truncates the final window at the end of the termination day, 16 of 30 days" do
        final = BillingCycle.order(:period_from).last
        expect(final.period_from).to eq(Time.zone.parse("2026-09-10T00:00:00Z"))
        # The window is the real termination instant — metering reads these boundaries.
        expect(final.period_to).to eq(Time.zone.parse("2026-09-25T00:00:00Z"))
        # Compared at the column's own precision: proration_ratio is numeric(30,10), so an
        # exact 16/30 never survives the round trip. This is the whole reason the engine's
        # Rational buys nothing past persistence.
        expect(final.proration_ratio).to eq(BigDecimal("0.5333333333"))
      end

      it "leaves the final cycle pending for the clock to invoice" do
        expect(BillingCycle.order(:period_from).last.status).to eq("pending")
      end

      it "marks the subscription terminated at the requested instant" do
        expect(seed.subscription.reload.status).to eq("terminated")
        expect(seed.subscription.terminated_at).to eq(Time.zone.parse("2026-09-25T00:00:00Z"))
      end

      it "creates no further cycle for a window after the termination" do
        expect { qa_bill(seed, start_on: "2026-09-25", end_on: "2026-10-10") }
          .not_to change(BillingCycle, :count)
      end

      # Contract C4 of the plan — the endpoint has no terminate flag, so the final
      # document cannot be produced through the API at all.
      it "cannot be billed through /bill once terminated" do
        qa_bill(seed, start_on: "2026-09-10", end_on: "2026-09-26")

        expect(response).to be_not_found_error("subscription")
      end
    end

    context "with proration: false" do
      subject(:seed) { qa_seed(id: "x1f") }

      before do
        qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")
        qa_terminate(seed, at: "2026-09-25")
      end

      it "carries the truncated window at the full fee ratio" do
        final = BillingCycle.order(:period_from).last
        expect(final.period_to).to eq(Time.zone.parse("2026-09-25T00:00:00Z"))
        expect(final.proration_ratio).to eq(1)
      end
    end
  end

  describe "X3 — window billing over three cycles" do
    subject(:seed) { qa_seed(id: "x3") }

    it "step 1 previews exactly three cycles" do
      qa_cycles(seed, start_on: "2026-08-10", end_on: "2026-11-10")

      expect(response).to have_http_status(:success)
      expect(json[:cycles].map { it[:period_from][0, 10] })
        .to eq(%w[2026-08-10 2026-09-10 2026-10-10])
    end

    # Contract C3: one invoice per cycle covered by the window. A single consolidated
    # document here is a High bug.
    it "step 2 emits three invoices, one per cycle" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-11-10")

      expect(response).to have_http_status(:success)
      expect(qa_invoice_totals(seed.customer)).to eq([15_000, 15_000, 15_000])
    end

    it "never bills a period that starts before the subscription" do
      qa_bill(seed, start_on: "2026-06-01", end_on: "2026-09-10")

      expect(qa_fees.map { it.properties["from_datetime"][0, 10] }).to eq(["2026-08-10"])
    end
  end

  describe "X4 — idempotency and mid-period no-op" do
    subject(:seed) { qa_seed(id: "x4") }

    it "bills the window once" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect(Invoice.count).to eq(1)
    end

    it "creates nothing on the same call repeated" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect { qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10") }
        .not_to change(Invoice, :count)
    end

    it "creates nothing for a window that crosses no boundary" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect { qa_bill(seed, start_on: "2026-09-15", end_on: "2026-09-15") }
        .not_to change(Invoice, :count)
    end

    it "leaves the invoice count untouched however often /cycles is read" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect do
        qa_cycles(seed, start_on: "2026-08-10", end_on: "2026-12-10")
        qa_cycles(seed, start_on: "2026-08-10", end_on: "2027-12-10")
      end.not_to change(Invoice, :count)
    end
  end

  describe "X5 — month-end clamping" do
    subject(:seed) { qa_seed(id: "x5", subscription_at: "2026-08-31") }

    # The anchor day must clamp into shorter months and RETURN to the 31st — P3 opens on
    # 2026-10-31, not on the 30th.
    it "step 1 clamps and returns to the anchor day, with no gap and no overlap" do
      qa_cycles(seed, start_on: "2026-08-31", end_on: "2026-12-31")

      expect(response).to have_http_status(:success)
      expect(json[:cycles].first(4).map { [it[:period_from][0, 10], it[:period_to][0, 10]] }).to eq(
        [
          %w[2026-08-31 2026-09-29],
          %w[2026-09-30 2026-10-30],
          %w[2026-10-31 2026-11-29],
          %w[2026-11-30 2026-12-30]
        ]
      )
    end

    it "step 2 bills 15000 per clamped period" do
      qa_bill(seed, start_on: "2026-08-31", end_on: "2026-12-31")

      expect(response).to have_http_status(:success)
      expect(qa_invoice_totals(seed.customer)).to eq([15_000, 15_000, 15_000, 15_000])
    end
  end

  describe "X6 — leap day" do
    context "X6a — monthly across Feb 29" do
      subject(:seed) { qa_seed(id: "x6a", subscription_at: "2028-01-31") }

      it "clamps January's 31st into February and reopens on the leap day" do
        qa_cycles(seed, start_on: "2028-01-31", end_on: "2028-03-31")

        expect(response).to have_http_status(:success)
        expect(json[:cycles].first(2).map { [it[:period_from][0, 10], it[:period_to][0, 10]] }).to eq(
          [%w[2028-01-31 2028-02-28], %w[2028-02-29 2028-03-30]]
        )
      end
    end

    context "X6b — yearly anchored on Feb 29" do
      subject(:seed) do
        qa_seed(
          id: "x6b",
          subscription_at: "2028-02-29",
          rates: [{code: "rate_x6b_v1", interval_unit: "year"}]
        )
      end

      it "clamps the 2029 boundary to Feb 28 and returns to Feb 29 in 2032" do
        qa_cycles(seed, start_on: "2028-02-29", end_on: "2033-03-01")

        expect(response).to have_http_status(:success)
        expect(json[:cycles].map { it[:period_from][0, 10] })
          .to eq(%w[2028-02-29 2029-02-28 2030-02-28 2031-02-28 2032-02-29])
      end
    end
  end

  describe "X7 — two cards, one invoice" do
    subject(:seed) do
      qa_seed(id: "x7").tap { qa_extra_card(seed: it, id: "x7", amount: "500.00", units: 1) }
    end

    it "step 1 previews one cycle per applied rate card" do
      qa_cycles(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect(response).to have_http_status(:success)
      expect(json[:cycles].map { it[:applied_rate_card_code] }).to match_array(%w[card_x7 card_x7_support])
    end

    it "step 2 produces a single invoice with two fees totalling 65000" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect(response).to have_http_status(:success)
      expect(Invoice.count).to eq(1)
      expect(Fee.pluck(:amount_cents)).to match_array([15_000, 50_000])
      expect(qa_invoice_totals(seed.customer)).to eq([65_000])
    end
  end

  describe "X8 — mixed cadences on one plan" do
    subject(:seed) do
      qa_seed(id: "x8").tap do
        qa_extra_card(seed: it, id: "x8", amount: "500.00", units: 1, interval_unit: "year")
      end
    end

    it "step 1 shows both cycle streams over a year" do
      qa_cycles(seed, start_on: "2026-08-10", end_on: "2027-08-10")

      expect(response).to have_http_status(:success)
      counts = json[:cycles].group_by { it[:applied_rate_card_code] }.transform_values(&:size)
      expect(counts).to eq("card_x8" => 12, "card_x8_support" => 1)
    end

    it "step 2 bills the monthly boundary alone — no yearly fee, no proration of it" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect(response).to have_http_status(:success)
      expect(qa_invoice_totals(seed.customer)).to eq([15_000])
    end

    it "step 2 bills both at the aligned boundary" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2027-08-10")

      expect(response).to have_http_status(:success)
      expect(Fee.where(amount_cents: 50_000).count).to eq(1)
      expect(Fee.where(amount_cents: 15_000).count).to eq(12)
    end
  end
end
