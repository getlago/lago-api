# frozen_string_literal: true

require "rails_helper"
require_relative "qa_plan_helper"

# QA plan — group CS (card structure).
#
# CS1a/b/c are QA-approved (2026-08-12 / 08-13). Their matrices are 2x2x2 over
# billing_timing x proration x billing_anchor_date; the amounts asserted are the plan's
# own "Expected" column. The plan's rows also count documents produced by the production
# clock at activation, which a request spec does not run — these examples assert what the
# /bill endpoint produces for the first period of each row, which is the figure the plan
# pins.
#
# CS2 and CS3 are QA returns: written, expected to fail, marked pending with the plan's
# own reason.
RSpec.describe "QA plan — CS (card structure)" do
  include QaPlanSeeds

  let(:organization) { create(:organization) }

  describe "CS1a — subscription starting now" do
    QaPlanSeeds::CS1A_MATRIX.each do |row, timing, proration, anchor, period, expected|
      context "row #{row} — #{timing} · proration #{proration} · anchor #{anchor}" do
        subject(:seed) do
          qa_seed(id: "cs1a_#{row}", timing:, proration:, anchor:, subscription_at: "2026-08-10")
        end

        it "step 1 previews the first period as #{period.first[0, 10]} → #{period.last[0, 10]}" do
          qa_cycles(seed, start_on: "2026-08-10", end_on: "2026-09-10")

          expect(response).to have_http_status(:success)
          first = json[:cycles].first
          expect([first[:period_from], first[:period_to]]).to eq(period)
        end

        it "step 2 bills the first period at #{expected} cents" do
          qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")

          expect(response).to have_http_status(:success)
          expect(qa_invoice_totals(seed.customer).first).to eq(expected)
        end
      end
    end

    # Rows 3 vs 4 are the plan's cleanest proration evidence: identical stub, only the
    # flag differs.
    it "isolates proration on an identical stub — 15000 with the flag off, 10645 with it on" do
      plain = qa_seed(id: "cs1a_p", timing: "arrears", proration: false, anchor: "2026-09-01")
      prorated = qa_seed(id: "cs1a_r", timing: "arrears", proration: true, anchor: "2026-09-01")

      qa_bill([plain, prorated], start_on: "2026-08-10", end_on: "2026-09-10")

      expect(qa_invoice_totals(plain.customer).first).to eq(15_000)
      expect(qa_invoice_totals(prorated.customer).first).to eq(10_645)
    end

    it "prices the prorated stub at unit 21.29 = 30 x 22/31" do
      seed = qa_seed(id: "cs1a_u", timing: "arrears", proration: true, anchor: "2026-09-01")

      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect(Fee.sole.precise_unit_amount.round(2)).to eq(21.29)
    end
  end

  describe "CS1b — subscription starting in the past (backdated)" do
    subject(:seed) { qa_seed(id: "cs1b_5", timing: "arrears", subscription_at: "2026-06-10") }

    it "step 1 previews the three elapsed cycles" do
      qa_cycles(seed, start_on: "2026-06-10", end_on: "2026-08-10", at: "2026-08-10")

      expect(response).to have_http_status(:success)
      expect(json[:cycles].map { it[:period_from] }).to eq(
        ["2026-06-10T00:00:00Z", "2026-07-10T00:00:00Z"]
      )
    end

    # The plan's catch-up assertion: every elapsed cycle gets exactly one invoice — gaps
    # filled, never consolidated.
    it "step 2 fills every elapsed cycle with its own invoice, 30000 in total" do
      qa_bill(seed, start_on: "2026-06-10", end_on: "2026-08-10")

      expect(response).to have_http_status(:success)
      expect(qa_invoice_totals(seed.customer)).to eq([15_000, 15_000])
    end

    it "step 2 never duplicates an already-billed cycle" do
      qa_bill(seed, start_on: "2026-06-10", end_on: "2026-08-10")
      qa_bill(seed, start_on: "2026-06-10", end_on: "2026-08-10")

      expect(Invoice.count).to eq(2)
    end

    context "with a billing anchor on the 1st" do
      subject(:seed) do
        qa_seed(id: "cs1b_7", timing: "arrears", subscription_at: "2026-06-10", anchor: "2026-09-01")
      end

      it "bills the stub at the full fee, then the calendar months" do
        qa_bill(seed, start_on: "2026-06-10", end_on: "2026-08-10")

        expect(qa_invoice_totals(seed.customer)).to eq([15_000, 15_000])
      end

      it "prorates the stub to 10500 = 150 x 21/30 when the flag is on" do
        prorated = qa_seed(
          id: "cs1b_8", timing: "arrears", proration: true,
          subscription_at: "2026-06-10", anchor: "2026-09-01"
        )

        qa_bill(prorated, start_on: "2026-06-10", end_on: "2026-08-10")

        expect(qa_invoice_totals(prorated.customer).first).to eq(10_500)
      end
    end
  end

  describe "CS1c — subscription starting in the future (pending)" do
    context "at creation, before the start date" do
      subject(:seed) do
        qa_seed(id: "cs1c_0", subscription_at: "2026-09-01", anchor: "2026-09-01", pending: true)
      end

      it "creates no document" do
        seed

        expect(Invoice.count).to eq(0)
      end

      # LAGO-1798 blocked this on staging: /cycles 404'd on a pending subscription.
      it "previews the future cycles instead of 404ing (LAGO-1798)" do
        qa_cycles(seed, start_on: "2026-09-01", end_on: "2026-10-15", at: "2026-08-11")

        expect(response).to have_http_status(:success)
        expect(json[:cycles].first[:period_from]).to eq("2026-09-01T00:00:00Z")
      end

      # The plan asks for this to be re-tested explicitly, since on staging it only
      # passed by accident (the 404 blocked everything).
      it "bills nothing for a window that closes before the start date" do
        seed

        qa_bill(seed, start_on: "2026-08-10", end_on: "2026-08-31", at: "2026-08-31")

        expect(Invoice.count).to eq(0)
      end
    end

    QaPlanSeeds::CS1C_MATRIX.each do |row, timing, proration, anchor, period, expected|
      context "row #{row} — #{timing} · proration #{proration} · anchor #{anchor}" do
        subject(:seed) do
          qa_seed(id: "cs1c_#{row}", timing:, proration:, anchor:, subscription_at: "2026-09-01")
        end

        it "step 1 previews the first period as #{period.first[0, 10]} → #{period.last[0, 10]}" do
          qa_cycles(seed, start_on: "2026-09-01", end_on: "2026-10-15")

          expect(response).to have_http_status(:success)
          first = json[:cycles].first
          expect([first[:period_from], first[:period_to]]).to eq(period)
        end

        it "step 2 bills the first period at #{expected} cents" do
          qa_bill(seed, start_on: "2026-09-01", end_on: "2026-10-15")

          expect(response).to have_http_status(:success)
          expect(qa_invoice_totals(seed.customer).first).to eq(expected)
        end
      end
    end

    # The live-seed pair QA re-verified on 2026-08-13: identical 19-day stub, only the
    # flag differs, 15000 vs 9194 (unit 18.388 = 30 x 19/31).
    it "reproduces the 19-day stub pair — 15000 vs 9194" do
      plain = qa_seed(id: "cs1c_g3", timing: "arrears", subscription_at: "2026-08-13", anchor: "2026-09-01")
      prorated = qa_seed(
        id: "cs1c_g4", timing: "arrears", proration: true,
        subscription_at: "2026-08-13", anchor: "2026-09-01"
      )

      qa_bill([plain, prorated], start_on: "2026-08-13", end_on: "2026-09-01")

      expect(qa_invoice_totals(plain.customer).first).to eq(15_000)
      expect(qa_invoice_totals(prorated.customer).first).to eq(9_194)
    end
  end

  describe "CS2 — display_on_invoice: false on a fixed card" do
    subject(:create_card) do
      post_with_token(
        organization,
        "/api/v2/rate_cards",
        {
          rate_card: {
            code: "card_cs2",
            name: "Seat card CS2",
            product_code: product.code,
            currency: "USD",
            billing_timing: "advance",
            proration: false,
            display_on_invoice: false
          }
        }
      )
    end

    let!(:product) { create(:product, :fixed, organization:, code: "seat_fee_cs2") }

    it "rejects it with not_allowed_for_product_type" do
      pending("QA return LAGO-1810 — display_on_invoice: false is accepted on a fixed card; it must be 422")
      create_card

      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error_details]).to eq(display_on_invoice: ["not_allowed_for_product_type"])
    end
  end

  describe "CS3 — applied pricing unit + conversion rate" do
    subject(:seed) do
      qa_seed(
        id: "cs3",
        card_extra: {applied_pricing_unit_code: "credits"},
        rates: [{code: "rate_cs3_v1", amount: "10", conversion: "0.50"}]
      )
    end

    let!(:pricing_unit) { create(:pricing_unit, organization:, code: "credits") }

    # QA recorded 5000 here (LAGO-1815: the conversion was dropped when the rate was
    # loaded into the cycle). It now converts: the return has been fixed.
    it "converts credits to currency on the fee — 50 credits x 0.50 = 2500" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect(qa_invoice_totals(seed.customer)).to eq([2_500])
    end

    it "carries the pricing unit onto the fee" do
      qa_bill(seed, start_on: "2026-08-10", end_on: "2026-09-10")

      expect(Fee.sole.pricing_unit_usage.pricing_unit).to eq(pricing_unit)
    end
  end
end
