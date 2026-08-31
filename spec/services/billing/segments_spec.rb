# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Segments do
  # Only effective_from is read, so the cases below stay free of the catalog.
  def rate(code, effective_from)
    Struct.new(:code, :effective_from).new(code, effective_from)
  end

  def windows(slices)
    slices.map { |slice| [slice.from.to_date.to_s, slice.to.to_date.to_s, slice.rate.code] }
  end

  let(:period) { Time.utc(2026, 9, 10)...Time.utc(2026, 10, 10) }

  describe ".within" do
    it "leaves a period whole when no rate changes inside it" do
      slices = described_class.within(period, rates: [rate("v1", Time.utc(2026, 1, 1))])

      expect(windows(slices)).to eq([["2026-09-10", "2026-10-10", "v1"]])
    end

    # QA plan R3b — a mid-period change splits the cycle into two priced windows.
    it "cuts the period where a rate takes effect inside it" do
      rates = [rate("v1", Time.utc(2026, 1, 1)), rate("v2", Time.utc(2026, 9, 25))]

      expect(windows(described_class.within(period, rates:))).to eq(
        [
          ["2026-09-10", "2026-09-25", "v1"],
          ["2026-09-25", "2026-10-10", "v2"]
        ]
      )
    end

    it "cuts once per change" do
      rates = [
        rate("v1", Time.utc(2026, 1, 1)),
        rate("v2", Time.utc(2026, 9, 20)),
        rate("v3", Time.utc(2026, 9, 30))
      ]

      expect(windows(described_class.within(period, rates:))).to eq(
        [
          ["2026-09-10", "2026-09-20", "v1"],
          ["2026-09-20", "2026-09-30", "v2"],
          ["2026-09-30", "2026-10-10", "v3"]
        ]
      )
    end

    # QA plan R3a — "effective date ON a boundary (no split)". The change is simply the
    # rate in force from the first instant, so there is nothing to cut.
    it "does not cut for a change landing on the period's start" do
      rates = [rate("v1", Time.utc(2026, 1, 1)), rate("v2", Time.utc(2026, 9, 10))]

      expect(windows(described_class.within(period, rates:))).to eq([["2026-09-10", "2026-10-10", "v2"]])
    end

    it "does not cut for a change landing on the period's end" do
      rates = [rate("v1", Time.utc(2026, 1, 1)), rate("v2", Time.utc(2026, 10, 10))]

      expect(windows(described_class.within(period, rates:))).to eq([["2026-09-10", "2026-10-10", "v1"]])
    end

    # QA plan R2 — "No rate = no fee is expected behavior, not an error."
    it "bills nothing while no rate is in force" do
      expect(described_class.within(period, rates: [rate("v1", Time.utc(2027, 1, 1))])).to be_empty
    end

    # QA plan R2 ruling — "first billable window = effective_from -> period end".
    it "starts billing at the first effective date when the period opens unpriced" do
      slices = described_class.within(period, rates: [rate("v1", Time.utc(2026, 9, 25))])

      expect(windows(slices)).to eq([["2026-09-25", "2026-10-10", "v1"]])
    end

    it "does not require the rates to be ordered" do
      rates = [rate("v2", Time.utc(2026, 9, 25)), rate("v1", Time.utc(2026, 1, 1))]

      expect(windows(described_class.within(period, rates:)).map(&:last)).to eq(%w[v1 v2])
    end

    it "returns nothing when there are no rates at all" do
      expect(described_class.within(period, rates: [])).to be_empty
    end

    # The slices of a cycle must tile it exactly: what a customer is billed for cannot
    # have a gap in it, and cannot bill the same day twice.
    it "tiles the period with no gap and no overlap" do
      rates = [
        rate("v1", Time.utc(2026, 1, 1)),
        rate("v2", Time.utc(2026, 9, 20)),
        rate("v3", Time.utc(2026, 9, 30))
      ]
      slices = described_class.within(period, rates:)

      expect(slices.first.from).to eq(period.begin)
      expect(slices.last.to).to eq(period.end)
      expect(slices.each_cons(2).all? { |before, after| before.to == after.from }).to be(true)
    end
  end
end
