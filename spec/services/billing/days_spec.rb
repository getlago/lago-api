# frozen_string_literal: true

require "rails_helper"

# Day ownership: a day belongs to the window holding its LOCAL midnight. Two places decide
# whose a day is — the proration denominator and the credit numerator — and when they used
# different rules a cut month billed 103.33%.
RSpec.describe Billing::Days do
  describe ".between" do
    it "counts the days a whole interval opens" do
      expect(described_class.between(Time.utc(2026, 6, 1), Time.utc(2026, 7, 1), timezone: "UTC")).to eq(30)
    end

    it "counts nothing for a window that opens and closes inside one day" do
      expect(described_class.between(Time.utc(2026, 6, 1, 9), Time.utc(2026, 6, 1, 17), timezone: "UTC")).to eq(0)
    end

    # The half-open window [from, to) owns the day at `from` only when it holds its opening.
    # Starting mid-morning, the 16th already belongs to whatever ran before.
    it "gives a day that has already opened to the window before it" do
      expect(described_class.between(Time.utc(2026, 6, 16, 9, 30), Time.utc(2026, 7, 1), timezone: "UTC")).to eq(14)
    end

    it "keeps the day when the window opens exactly on its midnight" do
      expect(described_class.between(Time.utc(2026, 6, 16), Time.utc(2026, 7, 1), timezone: "UTC")).to eq(15)
    end

    # The one shape that catches a timezone being ignored, and it has to be a CUT.
    #
    # Move both ends of a window by the same offset and a UTC-only reading lands on the right
    # answer by luck — the offsets cancel and the total is still 30. A cut does not cancel: the
    # window opens on a local midnight and the cut falls mid-day, so only one end shifts.
    # Dropping the timezone from #opening_date passes every other example in this file and
    # misprices both slices of a cut period for every customer outside UTC.
    it "shares a cut interval by local days, not by UTC days" do
      window = [Time.utc(2026, 6, 1, 4), Time.utc(2026, 7, 1, 4)] # Jun 1 -> Jul 1 in New York
      cut = Time.utc(2026, 6, 15, 12)                             # 08:00 on the 15th there

      before = described_class.between(window.first, cut, timezone: "America/New_York")
      after = described_class.between(cut, window.last, timezone: "America/New_York")

      expect([before, after]).to eq([15, 15])
    end

    # The two sides of a cut always add back up to the whole, whatever hour the cut lands
    # at. This is the invariant the 103% bug broke.
    it "splits an interval into shares that sum to it" do
      window = [Time.utc(2026, 3, 1), Time.utc(2026, 4, 1)]
      whole = described_class.between(*window, timezone: "UTC")

      [0, 9, 14, 23].each do |hour|
        cut = Time.utc(2026, 3, 15, hour)
        before = described_class.between(window.first, cut, timezone: "UTC")
        after = described_class.between(cut, window.last, timezone: "UTC")

        expect(before + after).to eq(whole)
      end
    end

    # New York loses an hour on 2026-03-08 and gains one on 2026-11-01, so March holds a
    # 23-hour day and November a 25-hour one. Neither is worth a different share: the day is
    # the unit, not the elapsed hours. Counting hours would make every month with a transition
    # total slightly wrong, and in opposite directions.
    it "counts a DST day as one day like any other" do
      march = described_class.between(Time.utc(2026, 3, 1, 5), Time.utc(2026, 4, 1, 4), timezone: "America/New_York")
      november = described_class.between(Time.utc(2026, 11, 1, 4), Time.utc(2026, 12, 1, 5), timezone: "America/New_York")

      expect([march, november]).to eq([31, 30])
    end
  end
end
