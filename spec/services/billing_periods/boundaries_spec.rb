# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingPeriods::Boundaries do
  def ruler(timezone:, anchor: "2026-02-01", count: 1, unit: "month")
    described_class.new(
      billing_anchor_date: Date.parse(anchor),
      interval_count: count,
      interval_unit: unit,
      timezone:
    )
  end

  describe "#at" do
    # `step = position * interval_count` is what makes anything other than "every 1 unit" work.
    it "steps by the whole interval, not by a single unit" do
      quarterly = ruler(timezone: "UTC", anchor: "2026-01-01", count: 3)

      expect(quarterly.at(0)).to eq(Time.utc(2026, 1, 1))
      expect(quarterly.at(2)).to eq(Time.utc(2026, 7, 1))
    end

    # The anchor is a reference day, not a floor, so a card starting before it still bills.
    it "goes backwards from the anchor" do
      expect(ruler(timezone: "UTC", anchor: "2026-02-01").at(-1)).to eq(Time.utc(2026, 1, 1))
    end

    # Every boundary comes from the anchor, never from the one before it, so a short month does
    # not drag the day down for good.
    it "does not let a month-end anchor drift" do
      month_end = ruler(timezone: "UTC", anchor: "2026-01-31")

      expect([month_end.at(1), month_end.at(2), month_end.at(3)].map(&:to_date))
        .to eq([Date.new(2026, 2, 28), Date.new(2026, 3, 31), Date.new(2026, 4, 30)])
    end

    # Everything else in the layer measures against these marks, so if they are not the
    # customer's midnight, nothing downstream can be either.
    it "lands on midnight in the customer's timezone" do
      tokyo = ruler(timezone: "Asia/Tokyo", anchor: "2026-03-01")

      expect(tokyo.at(0)).to eq(Time.utc(2026, 2, 28, 15))
      expect(tokyo.at(0).in_time_zone("Asia/Tokyo").strftime("%H:%M")).to eq("00:00")
    end
  end

  describe "#position_on_or_before" do
    # The definition, checked as a property rather than by example: the boundary it names is on
    # or before the instant, and the next one is after it. Everything else — the cheap estimate,
    # the step back when it overshoots, the integer division flooring for dates before the
    # anchor — is machinery in service of exactly that.
    [["day", 1], ["day", 10], ["week", 1], ["week", 2],
      ["month", 1], ["month", 3], ["year", 1]].each do |unit, count|
      it "brackets the instant for #{count} #{unit}(s)" do
        wrong = []

        ["2026-01-01", "2026-01-31", "2024-02-29"].each do |anchor|
          subject = ruler(timezone: "UTC", anchor:, count:, unit:)

          # Deliberately reaching well before the anchor: positions go negative there, and the
          # estimate must floor rather than truncate toward zero or it lands one too low.
          [-800, -370, -95, -31, -1, 0, 1, 45, 200, 900].each do |offset|
            instant = Date.parse(anchor).to_time(:utc) + offset.days
            position = subject.position_on_or_before(instant)

            next if subject.at(position) <= instant && subject.at(position + 1) > instant

            wrong << {anchor:, offset:, position:, at: subject.at(position), instant:}
          end
        end

        expect(wrong).to be_empty
      end
    end

    # Which DAY an instant belongs to is the customer's call, not UTC's. A caller handing over
    # a raw instant must get the same answer as one that converted first — otherwise forgetting
    # the conversion bills the wrong month instead of raising.
    #
    # Already Mar 1 01:00 in Tokyo, so it belongs to period 1, not period 0.
    it "reads the instant in the customer timezone, not in UTC" do
      tokyo = ruler(timezone: "Asia/Tokyo")
      instant = Time.utc(2026, 2, 28, 16, 0)

      expect(tokyo.position_on_or_before(instant)).to eq(1)
      expect(tokyo.position_on_or_before(instant.in_time_zone("Asia/Tokyo"))).to eq(1)
    end

    # The mirror case, behind UTC: still Feb 28 19:30 in New York, so still period 0.
    it "does not run ahead for a timezone behind UTC" do
      new_york = ruler(timezone: "America/New_York")
      instant = Time.utc(2026, 3, 1, 0, 30)

      expect(new_york.position_on_or_before(instant)).to eq(0)
    end

    it "goes negative before the anchor" do
      expect(ruler(timezone: "UTC").position_on_or_before(Time.utc(2026, 1, 15))).to eq(-1)
    end

    # Feb 15 sits in the period the 31st opened, which runs to Feb 28.
    it "reads a month-end anchor's short period" do
      expect(ruler(timezone: "UTC", anchor: "2026-01-31").position_on_or_before(Time.utc(2026, 2, 15))).to eq(0)
    end
  end

  describe "#ends_at" do
    # Consecutive periods have to tile the timeline: no hour belongs to two of them, and none
    # belongs to neither. Overlapping periods are what the database's exclusion constraint
    # refuses, and a gap would be a day nobody is billed for.
    [["day", 1], ["week", 2], ["month", 1], ["month", 3], ["year", 1]].each do |unit, count|
      it "tiles the timeline with no gap and no overlap, #{count} #{unit}(s)" do
        ["UTC", "America/New_York", "Asia/Kathmandu"].each do |timezone|
          subject = ruler(timezone:, anchor: "2026-01-31", count:, unit:)

          (-3..3).each do |position|
            closes = subject.ends_at(position)

            expect(closes).to be >= subject.at(position)
            expect(closes).to be < subject.at(position + 1)
            # And it closes the customer's day, not UTC's.
            expect(closes.in_time_zone(timezone)).to eq(closes.in_time_zone(timezone).end_of_day)
          end
        end
      end
    end

    it "closes the period out on the day before the next boundary" do
      june = ruler(timezone: "UTC", anchor: "2026-06-01")

      expect(june.ends_at(0)).to eq(Time.utc(2026, 6, 30).end_of_day)
      expect(june.ends_at(0)).to be < june.at(1)
    end

    # The anchor is the 31st, so the next boundary is Feb 28 and the period closes on the 27th.
    it "follows a month-end anchor into a short month" do
      expect(ruler(timezone: "UTC", anchor: "2026-01-31").ends_at(0)).to eq(Time.utc(2026, 2, 27).end_of_day)
    end
  end

  describe "#days_at" do
    # CALENDAR days, not elapsed time — `.to_date` is doing that on purpose, and it is what the
    # legacy engine does by truncating to DATE(). A month containing a clock change is an hour
    # short or an hour long, and it still has to count as all of its days: this number is the
    # denominator every prorated fee is divided by.
    it "counts calendar days through a clock change, in both directions" do
      spring = ruler(timezone: "America/New_York", anchor: "2026-03-01")
      autumn = ruler(timezone: "America/New_York", anchor: "2026-11-01")

      expect(spring.days_at(0)).to eq(31)
      expect(autumn.days_at(0)).to eq(30)

      # And the wall clock really did move, so measuring in seconds would have got both wrong.
      expect(spring.at(1) - spring.at(0)).to eq(31.days - 1.hour)
      expect(autumn.at(1) - autumn.at(0)).to eq(30.days + 1.hour)
    end

    it "spans the whole interval, not a single unit" do
      expect(ruler(timezone: "UTC", anchor: "2026-01-01", count: 3).days_at(0)).to eq(90)
      expect(ruler(timezone: "UTC", anchor: "2026-01-01", count: 2, unit: "week").days_at(0)).to eq(14)
    end

    it "measures the period at that index, boundary to boundary" do
      expect(ruler(timezone: "UTC", anchor: "2026-06-01").days_at(0)).to eq(30)
      expect(ruler(timezone: "UTC", anchor: "2026-01-01").days_at(1)).to eq(28)
      expect(ruler(timezone: "UTC", anchor: "2026-01-31").days_at(0)).to eq(28)
    end
  end

  describe "#share_of" do
    let(:june) { ruler(timezone: "UTC", anchor: "2026-06-01") }

    # The layer counts days two different ways — `days_at` subtracts Dates, `share_of` goes
    # through the shared util with its own rounding. Nobody had ever checked they agree. If they
    # disagree, a whole period stops coming to exactly 1 and every fee is short by a day.
    [["day", 1], ["week", 2], ["month", 1], ["month", 3], ["year", 1]].each do |unit, count|
      it "gives exactly 1 for a whole period, #{count} #{unit}(s)" do
        ["UTC", "America/New_York"].each do |timezone|
          subject = ruler(timezone:, anchor: "2026-01-31", count:, unit:)

          (-2..2).each do |position|
            expect(subject.share_of(position, subject.at(position), subject.ends_at(position))).to eq(1)
          end
        end
      end
    end

    it "measures a partial window against the whole period, not against itself" do
      # A card joining on the 16th of a 30-day month covers half of it, not all of it.
      expect(june.share_of(0, Time.utc(2026, 6, 16), june.ends_at(0))).to eq(15.fdiv(30))
    end

    # A slice that opens after the window closed has covered nothing. Reading the days as a
    # distance instead would credit back part of a period that never began.
    it "treats a window ending before it starts as empty, not as backwards" do
      expect(june.share_of(0, Time.utc(2026, 6, 20), Time.utc(2026, 6, 10))).to eq(0)
    end

    it "never runs over 1, however far the window reaches" do
      expect(june.share_of(0, Time.utc(2026, 6, 1), Time.utc(2027, 1, 1))).to eq(1)
    end
  end

  it "names the unit it cannot lay out rather than returning nothing" do
    expect { ruler(timezone: "UTC", unit: "fortnight").at(1) }
      .to raise_error(ArgumentError, /Invalid billing interval unit: fortnight/)
  end
end
