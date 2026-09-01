# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Interval do
  it "covers exactly the billing interval units the catalog allows" do
    expect(described_class::UNITS).to match_array(RateCardRate::BILLING_INTERVAL_UNITS.keys)
  end

  describe "validation" do
    it "rejects an unknown unit" do
      expect { described_class.new(count: 1, unit: :fortnight) }.to raise_error(ArgumentError, /Unknown interval unit/)
    end

    it "rejects a zero count" do
      expect { described_class.new(count: 0, unit: :month) }.to raise_error(ArgumentError, /must be positive/)
    end

    it "rejects a negative count" do
      expect { described_class.new(count: -1, unit: :month) }.to raise_error(ArgumentError, /must be positive/)
    end

    it "normalizes string inputs" do
      expect(described_class.new(count: "3", unit: "month")).to eq(described_class.new(count: 3, unit: :month))
    end
  end

  # The two override columns are nullable independently of each other, which is why this
  # reads four columns rather than composing two Intervals: a phase that only changes the
  # unit keeps the rate's count.
  describe ".from" do
    let(:rate) { build_stubbed(:rate_card_rate, billing_interval_count: 3, billing_interval_unit: "month") }

    it "reads the rate when there is no override" do
      expect(described_class.from(rate)).to eq(described_class.new(count: 3, unit: :month))
    end

    it "reads the override when it sets both columns" do
      override = build_stubbed(:rate_override, billing_interval_count: 2, billing_interval_unit: "week")

      expect(described_class.from(rate, override:)).to eq(described_class.new(count: 2, unit: :week))
    end

    it "keeps the rate's count when the override sets only the unit" do
      override = build_stubbed(:rate_override, billing_interval_count: nil, billing_interval_unit: "week")

      expect(described_class.from(rate, override:)).to eq(described_class.new(count: 3, unit: :week))
    end

    it "keeps the rate's unit when the override sets only the count" do
      override = build_stubbed(:rate_override, billing_interval_count: 2, billing_interval_unit: nil)

      expect(described_class.from(rate, override:)).to eq(described_class.new(count: 2, unit: :month))
    end

    it "falls back to the rate entirely when the override sets neither" do
      override = build_stubbed(:rate_override, billing_interval_count: nil, billing_interval_unit: nil)

      expect(described_class.from(rate, override:)).to eq(described_class.new(count: 3, unit: :month))
    end
  end

  describe "#advance" do
    [
      {count: 1, unit: :month, from: Time.utc(2022, 1, 31), steps: 1, expected: Time.utc(2022, 2, 28)},
      {count: 1, unit: :month, from: Time.utc(2022, 1, 31), steps: 2, expected: Time.utc(2022, 3, 31)},
      {count: 1, unit: :month, from: Time.utc(2022, 1, 31), steps: -1, expected: Time.utc(2021, 12, 31)},
      {count: 1, unit: :month, from: Time.utc(2022, 1, 31), steps: 0, expected: Time.utc(2022, 1, 31)},
      {count: 3, unit: :month, from: Time.utc(2022, 1, 31), steps: 1, expected: Time.utc(2022, 4, 30)},
      {count: 3, unit: :month, from: Time.utc(2022, 1, 1), steps: 2, expected: Time.utc(2022, 7, 1)},
      {count: 1, unit: :day, from: Time.utc(2022, 1, 31), steps: 10, expected: Time.utc(2022, 2, 10)},
      {count: 2, unit: :week, from: Time.utc(2022, 1, 31), steps: 1, expected: Time.utc(2022, 2, 14)},
      {count: 1, unit: :year, from: Time.utc(2024, 2, 29), steps: 1, expected: Time.utc(2025, 2, 28)}
    ].each do |test_case|
      it "moves #{test_case[:from].to_date} by #{test_case[:steps]} x #{test_case[:count]} #{test_case[:unit]}" do
        interval = described_class.new(count: test_case[:count], unit: test_case[:unit])

        expect(interval.advance(test_case[:from], test_case[:steps])).to eq(test_case[:expected])
      end
    end

    # Calendar passes a zone-aware timestamp, never a UTC one, and these are the two ways
    # that matters. Paris springs forward on Mar 29 2026, and Mar 1 00:00 there is Feb 28
    # 23:00 UTC — a different month.
    context "with a zone-aware timestamp" do
      let(:paris) { Time.find_zone("Europe/Paris") }
      let(:local_midnight) { paris.local(2026, 3, 1) }

      it "steps a month by the local date rather than the UTC one" do
        interval = described_class.new(count: 1, unit: :month)

        expect(interval.advance(local_midnight, 1)).to eq(paris.local(2026, 4, 1))
        expect(interval.advance(local_midnight.utc, 1)).to eq(Time.utc(2026, 3, 28, 23))
      end

      it "keeps the wall-clock time when a week crosses the transition" do
        interval = described_class.new(count: 1, unit: :week)
        result = interval.advance(local_midnight, 5)

        expect(result).to eq(paris.local(2026, 4, 5))
        expect(result.in_time_zone(paris)).to eq(result.in_time_zone(paris).beginning_of_day)
      end
    end

    # Month-ends only stay put because every step is derived from the same origin.
    # Accumulating one step at a time would collapse to Feb 28.
    it "does not drift when month-ends are re-derived from the same origin" do
      interval = described_class.new(count: 1, unit: :month)
      origin = Time.utc(2022, 1, 31)

      expect((0..3).map { interval.advance(origin, it) })
        .to eq([Time.utc(2022, 1, 31), Time.utc(2022, 2, 28), Time.utc(2022, 3, 31), Time.utc(2022, 4, 30)])
    end
  end

  describe "#steps_between" do
    [
      {count: 1, unit: :month, from: Time.utc(2022, 1, 31), to: Time.utc(2022, 1, 31), expected: 0},
      # Feb 15 has not reached the Feb 28 step, so no whole interval has closed.
      # The calendar grid would say 1 here; the correction brings it back to 0.
      {count: 1, unit: :month, from: Time.utc(2022, 1, 31), to: Time.utc(2022, 2, 15), expected: 0},
      {count: 1, unit: :month, from: Time.utc(2022, 1, 31), to: Time.utc(2022, 2, 28), expected: 1},
      {count: 1, unit: :month, from: Time.utc(2022, 1, 31), to: Time.utc(2021, 12, 15), expected: -2},
      {count: 3, unit: :month, from: Time.utc(2022, 1, 1), to: Time.utc(2022, 8, 1), expected: 2},
      {count: 3, unit: :month, from: Time.utc(2022, 1, 31), to: Time.utc(2022, 4, 15), expected: 0},
      {count: 3, unit: :month, from: Time.utc(2022, 1, 1), to: Time.utc(2021, 11, 1), expected: -1},
      {count: 1, unit: :day, from: Time.utc(2022, 1, 1), to: Time.utc(2022, 1, 10), expected: 9},
      {count: 3, unit: :day, from: Time.utc(2022, 1, 11), to: Time.utc(2022, 1, 1), expected: -4},
      {count: 1, unit: :week, from: Time.utc(2022, 1, 1), to: Time.utc(2022, 1, 15), expected: 2},
      {count: 1, unit: :week, from: Time.utc(2022, 1, 15), to: Time.utc(2022, 1, 1), expected: -2},
      {count: 1, unit: :year, from: Time.utc(2022, 6, 1), to: Time.utc(2025, 1, 1), expected: 2}
    ].each do |test_case|
      it "fits #{test_case[:expected]} x #{test_case[:count]} #{test_case[:unit]} " \
         "from #{test_case[:from].to_date} to #{test_case[:to].to_date}" do
        interval = described_class.new(count: test_case[:count], unit: test_case[:unit])

        expect(interval.steps_between(test_case[:from], test_case[:to])).to eq(test_case[:expected])
      end
    end

    # The defining property: `from` advanced by the answer never passes `to`, and one
    # more step always does.
    #
    # Checked across a matrix rather than a few chosen rows, because this is what
    # pins calendar_steps_between to overshooting by at most one. steps_between takes
    # a single step back; if a change ever made the bracket overshoot by two it would
    # silently return a wrong index, and this is what catches that.
    it "always lands on the last step at or before the target" do
      # The last two are zone-aware and sit on Paris's DST transition days, because that is
      # the type Calendar passes and a UTC-only matrix would never exercise it.
      froms = [
        Time.utc(2022, 1, 31),
        Time.utc(2024, 2, 29),
        Time.utc(2022, 7, 15),
        Time.utc(2021, 12, 1),
        Time.utc(2022, 6, 30),
        Time.find_zone("Europe/Paris").local(2026, 3, 29),
        Time.find_zone("Europe/Paris").local(2026, 10, 25)
      ]
      offsets = [-400, -95, -31, -30, -29, -1, 0, 1, 27, 28, 29, 30, 31, 32, 59, 90, 365, 366, 730]

      violations = described_class::UNITS.flat_map do |unit|
        [1, 3].flat_map do |count|
          interval = described_class.new(count:, unit:)

          froms.flat_map do |from|
            offsets.filter_map do |offset|
              to = from + offset.days
              steps = interval.steps_between(from, to)
              next if interval.advance(from, steps) <= to && interval.advance(from, steps + 1) > to

              "#{count} #{unit} from #{from.to_date} to #{to.to_date} gave #{steps}"
            end
          end
        end
      end

      expect(violations).to be_empty
    end
  end
end
