# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Calendar do
  subject(:calendar) { described_class.new(anchor_date:, interval:, timezone:) }

  let(:anchor_date) { Date.new(2022, 2, 1) }
  let(:interval) { Billing::Interval.new(count: 1, unit: :month) }
  let(:timezone) { "UTC" }

  def calendar_for(anchor, count, unit, timezone = "UTC")
    described_class.new(
      anchor_date: anchor,
      interval: Billing::Interval.new(count:, unit:),
      timezone:
    )
  end

  describe "#anchor" do
    it "starts at the beginning of the anchor day" do
      expect(calendar.anchor).to eq(Time.utc(2022, 2, 1))
    end

    context "with a customer timezone" do
      let(:timezone) { "America/New_York" }

      it "starts at the beginning of the anchor day in that timezone" do
        expect(calendar.anchor).to eq(Time.utc(2022, 2, 1, 5))
      end
    end
  end

  describe "#index_at" do
    # The step function: constant inside a period, turning exactly on the boundary.
    # Anchored on the 31st so month-end clamping is in play throughout.
    [
      {time: Time.utc(2022, 1, 30), expected: -1},
      {time: Time.utc(2022, 1, 31), expected: 0},
      {time: Time.utc(2022, 2, 15), expected: 0},
      {time: Time.utc(2022, 2, 27), expected: 0},
      {time: Time.utc(2022, 2, 28), expected: 1},
      {time: Time.utc(2022, 3, 31), expected: 2}
    ].each do |test_case|
      it "places #{test_case[:time].to_date} in period #{test_case[:expected]}" do
        subject = calendar_for(Date.new(2022, 1, 31), 1, :month)

        expect(subject.index_at(test_case[:time])).to eq(test_case[:expected])
      end
    end

    # Same instant, two timezones, two answers. Mar 1 02:00 UTC is still Feb 28 in
    # New York, so the March boundary has not been reached there yet.
    context "when the instant straddles a boundary in the customer timezone" do
      let(:time) { Time.utc(2022, 3, 1, 2) }

      it "counts the boundary as reached in UTC" do
        expect(calendar_for(Date.new(2022, 2, 1), 1, :month).index_at(time)).to eq(1)
      end

      it "does not count it as reached in New York" do
        expect(calendar_for(Date.new(2022, 2, 1), 1, :month, "America/New_York").index_at(time)).to eq(0)
      end
    end
  end

  describe "#period_at" do
    [
      {anchor: Date.new(2022, 2, 1), count: 1, unit: :month, time: Time.utc(2022, 2, 10),
       expected: Time.utc(2022, 2, 1)...Time.utc(2022, 3, 1)},
      # Before the anchor: the anchor is a reference day, not a start date.
      {anchor: Date.new(2022, 2, 1), count: 1, unit: :month, time: Time.utc(2022, 1, 10),
       expected: Time.utc(2022, 1, 1)...Time.utc(2022, 2, 1)},
      # Anchored on the 31st: February clamps to the 28th...
      {anchor: Date.new(2022, 1, 31), count: 1, unit: :month, time: Time.utc(2022, 2, 15),
       expected: Time.utc(2022, 1, 31)...Time.utc(2022, 2, 28)},
      # ...and March goes back to the 31st instead of dragging along at the 28th.
      {anchor: Date.new(2022, 1, 31), count: 1, unit: :month, time: Time.utc(2022, 3, 1),
       expected: Time.utc(2022, 2, 28)...Time.utc(2022, 3, 31)},
      {anchor: Date.new(2022, 1, 1), count: 3, unit: :month, time: Time.utc(2022, 8, 1),
       expected: Time.utc(2022, 7, 1)...Time.utc(2022, 10, 1)},
      {anchor: Date.new(2022, 1, 1), count: 1, unit: :week, time: Time.utc(2022, 1, 25),
       expected: Time.utc(2022, 1, 22)...Time.utc(2022, 1, 29)},
      {anchor: Date.new(2022, 1, 1), count: 1, unit: :day, time: Time.utc(2022, 2, 15, 12),
       expected: Time.utc(2022, 2, 15)...Time.utc(2022, 2, 16)},
      {anchor: Date.new(2024, 2, 29), count: 1, unit: :year, time: Time.utc(2025, 3, 1),
       expected: Time.utc(2025, 2, 28)...Time.utc(2026, 2, 28)}
    ].each do |test_case|
      it "puts #{test_case[:time].to_date} in #{test_case[:expected].begin.to_date}..." \
         "#{test_case[:expected].end.to_date} at #{test_case[:count]} #{test_case[:unit]} " \
         "anchored on #{test_case[:anchor]}" do
        subject = calendar_for(test_case[:anchor], test_case[:count], test_case[:unit])

        expect(subject.period_at(test_case[:time])).to eq(test_case[:expected])
      end
    end

    it "excludes its end, so the boundary belongs to the next period" do
      period = calendar.period_at(Time.utc(2022, 2, 10))

      expect(period.exclude_end?).to be(true)
    end

    it "covers the last instant before the boundary but not the boundary" do
      period = calendar.period_at(Time.utc(2022, 2, 10))

      expect(period.cover?(Time.utc(2022, 2, 28, 23, 59, 59))).to be(true)
      expect(period.cover?(Time.utc(2022, 3, 1))).to be(false)
    end
  end

  describe "#days_in_period_at" do
    [
      {anchor: Date.new(2022, 2, 1), count: 1, unit: :month, time: Time.utc(2022, 2, 10), expected: 28},
      {anchor: Date.new(2024, 2, 1), count: 1, unit: :month, time: Time.utc(2024, 2, 10), expected: 29},
      {anchor: Date.new(2022, 6, 1), count: 1, unit: :month, time: Time.utc(2022, 6, 10), expected: 30},
      {anchor: Date.new(2022, 7, 1), count: 1, unit: :month, time: Time.utc(2022, 7, 10), expected: 31},
      {anchor: Date.new(2022, 1, 1), count: 3, unit: :month, time: Time.utc(2022, 2, 10), expected: 90},
      {anchor: Date.new(2022, 1, 1), count: 2, unit: :week, time: Time.utc(2022, 1, 10), expected: 14}
    ].each do |test_case|
      it "counts #{test_case[:expected]} days in the #{test_case[:count]} #{test_case[:unit]} " \
         "period covering #{test_case[:time].to_date}" do
        subject = calendar_for(test_case[:anchor], test_case[:count], test_case[:unit])

        expect(subject.days_in_period_at(test_case[:time])).to eq(test_case[:expected])
      end
    end
  end

  describe "#elapsed_ratio" do
    subject(:calendar) { calendar_for(Date.new(2022, 6, 1), 1, :month) }

    it "is 1.0 for a whole period" do
      expect(calendar.elapsed_ratio(Time.utc(2022, 6, 1), Time.utc(2022, 7, 1))).to eq(1.0)
    end

    it "prorates a window clamped at the start" do
      expect(calendar.elapsed_ratio(Time.utc(2022, 6, 1), Time.utc(2022, 6, 16))).to eq(0.5)
    end

    it "prorates a window clamped at both ends" do
      expect(calendar.elapsed_ratio(Time.utc(2022, 6, 28), Time.utc(2022, 7, 1))).to eq(0.1)
    end

    # The denominator is the period containing `from`, so a window reaching past the
    # boundary would be measured against the wrong length. A short straddling window
    # returns a plausible number, which is why this is rejected rather than capped.
    it "rejects a window crossing the boundary" do
      expect { calendar.elapsed_ratio(Time.utc(2022, 6, 29), Time.utc(2022, 7, 2)) }
        .to raise_error(ArgumentError, /crosses the boundary/)
    end

    it "rejects a window spanning several periods" do
      expect { calendar.elapsed_ratio(Time.utc(2022, 6, 1), Time.utc(2022, 8, 1)) }
        .to raise_error(ArgumentError, /crosses the boundary/)
    end

    it "rejects a window ending before it starts" do
      expect { calendar.elapsed_ratio(Time.utc(2022, 6, 20), Time.utc(2022, 6, 10)) }
        .to raise_error(ArgumentError, /precedes its start/)
    end

    it "is 0.0 for an empty window" do
      expect(calendar.elapsed_ratio(Time.utc(2022, 6, 1), Time.utc(2022, 6, 1))).to eq(0.0)
    end

    # A day begun counts as a whole day. This is the v1 billing rule, carried by the
    # ceil in Utils::Datetime — a policy, not an implementation detail, so it is pinned
    # here rather than left to emerge.
    context "when the window ends part-way through a day" do
      it "counts a full day for a termination a few hours in" do
        expect(calendar.elapsed_ratio(Time.utc(2022, 6, 1), Time.utc(2022, 6, 1, 9))).to eq(1.fdiv(30))
      end

      it "counts the started day in full" do
        expect(calendar.elapsed_ratio(Time.utc(2022, 6, 1), Time.utc(2022, 6, 15, 14, 30))).to eq(15.fdiv(30))
      end

      it "counts one day less when the window ends exactly on midnight" do
        expect(calendar.elapsed_ratio(Time.utc(2022, 6, 1), Time.utc(2022, 6, 15))).to eq(14.fdiv(30))
      end
    end

    # A DST transition makes one day 23 or 25 hours long. Without the timezone-aware
    # day count these periods would come out as 30.96 and 30.04 days, and a full
    # period would silently prorate.
    context "when a daylight saving transition falls inside the period" do
      let(:new_york) { Time.find_zone!("America/New_York") }

      it "is 1.0 over a spring forward" do
        subject = calendar_for(Date.new(2026, 3, 1), 1, :month, "America/New_York")

        expect(subject.elapsed_ratio(new_york.local(2026, 3, 1), new_york.local(2026, 4, 1))).to eq(1.0)
      end

      it "is 1.0 over a fall back" do
        subject = calendar_for(Date.new(2026, 11, 1), 1, :month, "America/New_York")

        expect(subject.elapsed_ratio(new_york.local(2026, 11, 1), new_york.local(2026, 12, 1))).to eq(1.0)
      end
    end
  end

  # Scenarios lifted from the Plan v2 QA plan (2026-08-10). These are the boundaries QA
  # signs off against, so they are pinned here against the pure calendar rather than only
  # through a billing run.
  describe "QA plan v2 scenarios" do
    def walk(subject, from, count)
      cursor = from

      Array.new(count) do
        period = subject.period_at(cursor)
        cursor = period.end
        period
      end
    end

    # BC — the cycle matrix: every billing_interval_unit x count, anchored on the signing
    # day. Bounds are shown inclusive in the plan, so the exclusive end is the day after.
    [
      {label: "day x 1", count: 1, unit: :day, bounds: ["2026-08-10", "2026-08-10", "2026-08-11", "2026-08-11"]},
      {label: "day x 45", count: 45, unit: :day, bounds: ["2026-08-10", "2026-09-23", "2026-09-24", "2026-11-07"]},
      {label: "week x 1", count: 1, unit: :week, bounds: ["2026-08-10", "2026-08-16", "2026-08-17", "2026-08-23"]},
      {label: "week x 4", count: 4, unit: :week, bounds: ["2026-08-10", "2026-09-06", "2026-09-07", "2026-10-04"]},
      {label: "month x 3", count: 3, unit: :month, bounds: ["2026-08-10", "2026-11-09", "2026-11-10", "2027-02-09"]},
      {label: "month x 6", count: 6, unit: :month, bounds: ["2026-08-10", "2027-02-09", "2027-02-10", "2027-08-09"]},
      {label: "year x 1", count: 1, unit: :year, bounds: ["2026-08-10", "2027-08-09", "2027-08-10", "2028-08-09"]},
      {label: "year x 2", count: 2, unit: :year, bounds: ["2026-08-10", "2028-08-09", "2028-08-10", "2030-08-09"]}
    ].each do |test_case|
      it "BC: bounds the first two #{test_case[:label]} cycles" do
        subject = calendar_for(Date.new(2026, 8, 10), test_case[:count], test_case[:unit])
        inclusive = walk(subject, Time.utc(2026, 8, 10), 2)
          .flat_map { |period| [period.begin.to_date.to_s, (period.end - 1.day).to_date.to_s] }

        expect(inclusive).to eq(test_case[:bounds])
      end
    end

    # X5 — "A subscription anchored on the 31st clamps to shorter month-ends but must
    # RETURN to the 31st — no permanent drift."
    it "X5: returns to the 31st after clamping to shorter months" do
      subject = calendar_for(Date.new(2026, 8, 31), 1, :month)

      expect(walk(subject, Time.utc(2026, 8, 31), 4).map { |period| period.begin.to_date }).to eq(
        [Date.new(2026, 8, 31), Date.new(2026, 9, 30), Date.new(2026, 10, 31), Date.new(2026, 11, 30)]
      )
    end

    # X6a — monthly across a leap February: the clamped boundary lands on Feb 29.
    it "X6a: clamps into a leap February and out again" do
      subject = calendar_for(Date.new(2028, 1, 31), 1, :month)

      expect(walk(subject, Time.utc(2028, 1, 31), 2).map { |period| period.begin.to_date })
        .to eq([Date.new(2028, 1, 31), Date.new(2028, 2, 29)])
    end

    # X6b — "Boundary 2029 = Feb 28 (clamped); the 2032 boundary returns to Feb 29."
    it "X6b: a yearly anchor on Feb 29 returns to Feb 29 in the next leap year" do
      subject = calendar_for(Date.new(2028, 2, 29), 1, :year)

      expect(walk(subject, Time.utc(2028, 2, 29), 5).map { |period| period.begin.to_date }).to eq(
        [
          Date.new(2028, 2, 29),
          Date.new(2029, 2, 28),
          Date.new(2030, 2, 28),
          Date.new(2031, 2, 28),
          Date.new(2032, 2, 29)
        ]
      )
    end

    # AN1/AN2 — signing on Aug 20 with the anchor on Sep 1 yields the stub Aug 20 -> Aug 31
    # and then the anchored month. CS1a pins the stub's denominator as the containing
    # anchored period (Aug 1 -> Sep 1, 31 days), not the following one.
    it "AN1: an anchor ahead of the signing date opens a stub cycle" do
      subject = calendar_for(Date.new(2026, 9, 1), 1, :month)
      signed_at = Time.utc(2026, 8, 20)
      stub = subject.period_at(signed_at)

      expect(stub).to eq(Time.utc(2026, 8, 1)...Time.utc(2026, 9, 1))
      expect(subject.days_in_period_at(signed_at)).to eq(31)
      expect(subject.elapsed_ratio(signed_at, stub.end)).to eq(12.fdiv(31))
      expect(subject.period_at(stub.end)).to eq(Time.utc(2026, 9, 1)...Time.utc(2026, 10, 1))
    end
  end

  describe "timezone handling" do
    # Boundaries are calendar positions, not fixed offsets from UTC. If `advance` ever
    # did UTC arithmetic instead, every boundary after a transition would shift by an
    # hour — and containment and contiguity would both still hold, so the invariants
    # below would not catch it.
    it "keeps every boundary at local midnight through a daylight saving transition" do
      subject = calendar_for(Date.new(2026, 1, 1), 1, :month, "America/New_York")
      starts = (1..12).map { |month| subject.period_at(Time.utc(2026, month, 15, 12)).begin }

      expect(starts.map { |start| [start.hour, start.min] }.uniq).to eq([[0, 0]])
      expect(starts.map(&:utc_offset).uniq).to match_array([-5 * 3600, -4 * 3600])
    end

    it "anchors periods at local midnight in a half-hour offset timezone" do
      subject = calendar_for(Date.new(2022, 6, 1), 1, :month, "Asia/Kolkata")
      period = subject.period_at(Time.utc(2022, 6, 15))

      expect([period.begin.hour, period.begin.min]).to eq([0, 0])
      expect(period.begin.utc_offset).to eq((5 * 3600) + 1800)
      expect(subject.days_in_period_at(Time.utc(2022, 6, 15))).to eq(30)
    end
  end

  # The two invariants everything downstream assumes, stated only through the public
  # API and checked across a matrix rather than a few chosen rows.
  describe "invariants" do
    let(:anchors) do
      [Date.new(2022, 1, 31), Date.new(2024, 2, 29), Date.new(2022, 7, 15), Date.new(2021, 12, 1)]
    end
    let(:timezones) { ["UTC", "America/New_York", "Asia/Tokyo"] }
    let(:offsets) { [-400, -95, -31, -30, -1, 0, 1, 27, 28, 30, 31, 59, 90, 365, 366] }
    # Real instants are rarely midnight, and the ones just inside a boundary are where
    # an off-by-one would show.
    let(:times_of_day) { [0.seconds, 7.hours + 31.minutes, 23.hours + 59.minutes] }

    it "always returns a period containing the instant" do
      violations = each_case do |subject, time, label|
        period = subject.period_at(time)
        next if period.cover?(time)

        "#{label} at #{time}: got #{period}"
      end

      expect(violations).to be_empty
    end

    # A boundary is the exclusive end of one period, so the period containing it must
    # start exactly there. Anything else is a gap or an overlap.
    it "never leaves a gap or an overlap between consecutive periods" do
      violations = each_case do |subject, time, label|
        boundary = subject.period_at(time).end
        next if subject.period_at(boundary).begin == boundary

        "#{label} at #{time}: the period after #{boundary} does not start there"
      end

      expect(violations).to be_empty
    end

    def each_case
      Billing::Interval::UNITS.flat_map do |unit|
        [1, 3].flat_map do |count|
          timezones.flat_map do |timezone|
            anchors.flat_map do |anchor|
              subject = calendar_for(anchor, count, unit, timezone)

              offsets.flat_map do |offset|
                times_of_day.filter_map do |time_of_day|
                  time = anchor.in_time_zone(timezone) + offset.days + time_of_day

                  yield(subject, time, "#{count} #{unit} on #{anchor} in #{timezone}")
                end
              end
            end
          end
        end
      end
    end
  end
end
