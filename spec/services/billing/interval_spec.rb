# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Interval do
  # A rate and an override are duck-typed here on purpose: Interval reads the two cadence
  # fields and knows nothing else about them.
  cadence = Struct.new(:billing_interval_count, :billing_interval_unit, keyword_init: true)

  describe "UNITS" do
    it "is the four supported calendar units" do
      expect(described_class::UNITS).to eq(%i[day week month year])
    end
  end

  describe ".new" do
    it "symbolizes a string unit" do
      expect(described_class.new(count: 1, unit: "month")).to eq(described_class.new(count: 1, unit: :month))
    end

    it "raises on an unknown unit" do
      expect { described_class.new(count: 1, unit: :fortnight) }.to raise_error(ArgumentError, /unknown interval unit/)
    end

    it "raises on a nil unit" do
      expect { described_class.new(count: 1, unit: nil) }.to raise_error(ArgumentError, /unknown interval unit/)
    end

    it "raises on a zero count" do
      expect { described_class.new(count: 0, unit: :month) }.to raise_error(ArgumentError, /positive integer/)
    end

    it "raises on a negative count" do
      expect { described_class.new(count: -1, unit: :month) }.to raise_error(ArgumentError, /positive integer/)
    end

    it "raises on a non-integer count" do
      expect { described_class.new(count: 1.5, unit: :month) }.to raise_error(ArgumentError, /positive integer/)
    end

    it "is frozen" do
      expect(described_class.new(count: 1, unit: :month)).to be_frozen
    end
  end

  describe ".for" do
    let(:rate) { cadence.new(billing_interval_count: 3, billing_interval_unit: "month") }

    it "reads the cadence off the rate when there is no override" do
      expect(described_class.for(rate)).to eq(described_class.new(count: 3, unit: :month))
    end

    it "reads the cadence off the rate when the override is nil" do
      expect(described_class.for(rate, override: nil)).to eq(described_class.new(count: 3, unit: :month))
    end

    it "takes both fields from the override when it sets both" do
      override = cadence.new(billing_interval_count: 2, billing_interval_unit: "week")

      expect(described_class.for(rate, override:)).to eq(described_class.new(count: 2, unit: :week))
    end

    it "keeps the rate count when the override only sets the unit" do
      override = cadence.new(billing_interval_count: nil, billing_interval_unit: "week")

      expect(described_class.for(rate, override:)).to eq(described_class.new(count: 3, unit: :week))
    end

    it "keeps the rate unit when the override only sets the count" do
      override = cadence.new(billing_interval_count: 2, billing_interval_unit: nil)

      expect(described_class.for(rate, override:)).to eq(described_class.new(count: 2, unit: :month))
    end

    it "falls back to the rate when the override sets neither field" do
      override = cadence.new(billing_interval_count: nil, billing_interval_unit: nil)

      expect(described_class.for(rate, override:)).to eq(described_class.new(count: 3, unit: :month))
    end

    it "raises when the rate carries no unit and the override does not supply one" do
      unitless = cadence.new(billing_interval_count: 1, billing_interval_unit: nil)

      expect { described_class.for(unitless) }.to raise_error(ArgumentError, /unknown interval unit/)
    end
  end

  describe "#advance" do
    it "returns a Date for a Date" do
      expect(described_class.new(count: 1, unit: :month).advance(Date.new(2024, 1, 15), 1)).to eq(Date.new(2024, 2, 15))
    end

    it "returns a Time for a Time" do
      moved = described_class.new(count: 1, unit: :month).advance(Time.utc(2024, 1, 15, 9, 30), 1)

      expect(moved).to eq(Time.utc(2024, 2, 15, 9, 30))
    end

    it "returns a TimeWithZone for a TimeWithZone" do
      timestamp = Time.find_zone!("Europe/Paris").local(2024, 1, 15, 9, 30)

      expect(described_class.new(count: 1, unit: :month).advance(timestamp, 1)).to be_a(ActiveSupport::TimeWithZone)
    end

    it "returns the timestamp itself for zero steps" do
      expect(described_class.new(count: 3, unit: :month).advance(Date.new(2024, 1, 15), 0)).to eq(Date.new(2024, 1, 15))
    end

    it "moves backwards for negative steps" do
      expect(described_class.new(count: 1, unit: :month).advance(Date.new(2024, 1, 31), -1)).to eq(Date.new(2023, 12, 31))
    end

    context "with every unit and count" do
      let(:start) { Date.new(2024, 1, 1) }

      it "advances days" do
        landings = [1, 2, 3, 12].map { |count| described_class.new(count:, unit: :day).advance(start, 1) }

        expect(landings).to eq([Date.new(2024, 1, 2), Date.new(2024, 1, 3), Date.new(2024, 1, 4), Date.new(2024, 1, 13)])
      end

      it "advances weeks" do
        landings = [1, 2, 3, 12].map { |count| described_class.new(count:, unit: :week).advance(start, 1) }

        expect(landings).to eq([Date.new(2024, 1, 8), Date.new(2024, 1, 15), Date.new(2024, 1, 22), Date.new(2024, 3, 25)])
      end

      it "advances months" do
        landings = [1, 2, 3, 12].map { |count| described_class.new(count:, unit: :month).advance(start, 1) }

        expect(landings).to eq([Date.new(2024, 2, 1), Date.new(2024, 3, 1), Date.new(2024, 4, 1), Date.new(2025, 1, 1)])
      end

      it "advances years" do
        landings = [1, 2, 3, 12].map { |count| described_class.new(count:, unit: :year).advance(start, 1) }

        expect(landings).to eq([Date.new(2025, 1, 1), Date.new(2026, 1, 1), Date.new(2027, 1, 1), Date.new(2036, 1, 1)])
      end
    end

    context "with a month-end anchor" do
      subject(:interval) { described_class.new(count: 1, unit: :month) }

      it "clamps and does not drift over 14 months, including a leap February" do
        boundaries = (1..14).map { |step| interval.advance(Date.new(2023, 1, 31), step) }

        expect(boundaries).to eq(
          [
            Date.new(2023, 2, 28),
            Date.new(2023, 3, 31),
            Date.new(2023, 4, 30),
            Date.new(2023, 5, 31),
            Date.new(2023, 6, 30),
            Date.new(2023, 7, 31),
            Date.new(2023, 8, 31),
            Date.new(2023, 9, 30),
            Date.new(2023, 10, 31),
            Date.new(2023, 11, 30),
            Date.new(2023, 12, 31),
            Date.new(2024, 1, 31),
            Date.new(2024, 2, 29),
            Date.new(2024, 3, 31)
          ]
        )
      end

      it "clamps the 31st into a leap February" do
        expect(interval.advance(Date.new(2024, 1, 31), 1)).to eq(Date.new(2024, 2, 29))
      end

      it "clamps a quarterly step landing on a leap February" do
        expect(described_class.new(count: 3, unit: :month).advance(Date.new(2023, 11, 30), 1)).to eq(Date.new(2024, 2, 29))
      end

      it "clamps Feb 29 to Feb 28 a year later" do
        expect(described_class.new(count: 1, unit: :year).advance(Date.new(2024, 2, 29), 1)).to eq(Date.new(2025, 2, 28))
      end
    end

    context "when a DST transition falls inside the range" do
      let(:paris) { Time.find_zone!("Europe/Paris") }

      it "keeps the wall-clock time when the day is 23 hours long" do
        expect(described_class.new(count: 1, unit: :day).advance(paris.local(2024, 3, 30, 12, 0), 1))
          .to eq(paris.local(2024, 3, 31, 12, 0))
      end

      it "keeps the wall-clock time when the day is 25 hours long" do
        expect(described_class.new(count: 1, unit: :day).advance(paris.local(2024, 10, 26, 12, 0), 1))
          .to eq(paris.local(2024, 10, 27, 12, 0))
      end

      it "keeps local midnight across a monthly step spanning a transition" do
        expect(described_class.new(count: 1, unit: :month).advance(paris.local(2024, 3, 1, 0, 0), 1))
          .to eq(paris.local(2024, 4, 1, 0, 0))
      end
    end
  end

  describe "#steps_between" do
    it "is zero between a timestamp and itself" do
      expect(described_class.new(count: 1, unit: :month).steps_between(Date.new(2024, 1, 15), Date.new(2024, 1, 15))).to eq(0)
    end

    context "with a month-end anchor" do
      subject(:interval) { described_class.new(count: 1, unit: :month) }

      let(:anchor) { Date.new(2023, 1, 31) }

      it "counts Feb 27 as step 0" do
        expect(interval.steps_between(anchor, Date.new(2023, 2, 27))).to eq(0)
      end

      it "counts Feb 28 as step 1" do
        expect(interval.steps_between(anchor, Date.new(2023, 2, 28))).to eq(1)
      end

      it "counts Mar 30 as step 1" do
        expect(interval.steps_between(anchor, Date.new(2023, 3, 30))).to eq(1)
      end

      it "counts Mar 31 as step 2" do
        expect(interval.steps_between(anchor, Date.new(2023, 3, 31))).to eq(2)
      end

      it "counts Feb 28 of a leap year as step 12" do
        expect(interval.steps_between(anchor, Date.new(2024, 2, 28))).to eq(12)
      end

      it "counts Feb 29 of a leap year as step 13" do
        expect(interval.steps_between(anchor, Date.new(2024, 2, 29))).to eq(13)
      end
    end

    context "with a timestamp before the anchor" do
      subject(:interval) { described_class.new(count: 1, unit: :month) }

      let(:anchor) { Date.new(2024, 2, 1) }

      it "is -1 for the day before the anchor" do
        expect(interval.steps_between(anchor, Date.new(2024, 1, 31))).to eq(-1)
      end

      it "is -1 for the start of the previous window" do
        expect(interval.steps_between(anchor, Date.new(2024, 1, 1))).to eq(-1)
      end

      it "is -2 just before the start of the previous window" do
        expect(interval.steps_between(anchor, Date.new(2023, 12, 31))).to eq(-2)
      end

      it "is -13 thirteen months earlier" do
        expect(interval.steps_between(anchor, Date.new(2023, 1, 31))).to eq(-13)
      end

      it "clamps correctly going backwards from a month end" do
        expect(interval.steps_between(Date.new(2023, 3, 31), Date.new(2023, 2, 27))).to eq(-2)
      end
    end

    context "with a time of day" do
      subject(:interval) { described_class.new(count: 1, unit: :day) }

      let(:anchor) { Time.utc(2024, 1, 1, 10, 0) }

      it "does not count a step that has not been reached yet" do
        expect(interval.steps_between(anchor, Time.utc(2024, 1, 2, 9, 59))).to eq(0)
      end

      it "counts a step reached exactly" do
        expect(interval.steps_between(anchor, Time.utc(2024, 1, 2, 10, 0))).to eq(1)
      end

      it "does not count a partial step backwards" do
        expect(interval.steps_between(anchor, Time.utc(2023, 12, 31, 10, 1))).to eq(-1)
      end

      it "counts a whole step backwards" do
        expect(interval.steps_between(anchor, Time.utc(2023, 12, 31, 9, 59))).to eq(-2)
      end
    end

    context "with every unit and count" do
      it "counts days" do
        steps = [1, 2, 3, 12].map { |count| described_class.new(count:, unit: :day).steps_between(Date.new(2024, 1, 1), Date.new(2024, 1, 25)) }

        expect(steps).to eq([24, 12, 8, 2])
      end

      it "counts weeks" do
        steps = [1, 2, 3, 12].map { |count| described_class.new(count:, unit: :week).steps_between(Date.new(2024, 1, 1), Date.new(2024, 12, 31)) }

        expect(steps).to eq([52, 26, 17, 4])
      end

      it "counts months" do
        steps = [1, 2, 3, 12].map { |count| described_class.new(count:, unit: :month).steps_between(Date.new(2024, 1, 1), Date.new(2026, 3, 1)) }

        expect(steps).to eq([26, 13, 8, 2])
      end

      it "counts years" do
        steps = [1, 2, 3, 12].map { |count| described_class.new(count:, unit: :year).steps_between(Date.new(2000, 1, 1), Date.new(2024, 1, 1)) }

        expect(steps).to eq([24, 12, 8, 2])
      end
    end

    # The defining property: steps_between is the largest n with advance(from, n) <= to,
    # so a boundary is its own step and the day before it is the previous one.
    context "when inverting advance" do
      %i[day week month year].each do |unit|
        [1, 2, 3, 12].each do |count|
          it "round-trips every step of #{count} #{unit}" do
            interval = described_class.new(count:, unit:)
            from = Date.new(2023, 1, 31)

            round_tripped = (-20..20).map do |step|
              landing = interval.advance(from, step)
              [interval.steps_between(from, landing), interval.steps_between(from, landing - 1)]
            end

            expect(round_tripped).to eq((-20..20).map { |step| [step, step - 1] })
          end
        end
      end
    end

    context "when a DST transition falls inside the range" do
      let(:paris) { Time.find_zone!("Europe/Paris") }

      it "counts a 23-hour day as one day" do
        expect(described_class.new(count: 1, unit: :day).steps_between(paris.local(2024, 3, 30, 12, 0), paris.local(2024, 3, 31, 12, 0))).to eq(1)
      end

      it "counts a 25-hour day as one day" do
        expect(described_class.new(count: 1, unit: :day).steps_between(paris.local(2024, 10, 26, 12, 0), paris.local(2024, 10, 27, 12, 0))).to eq(1)
      end

      it "counts a March month as one month" do
        expect(described_class.new(count: 1, unit: :month).steps_between(paris.local(2024, 3, 1, 0, 0), paris.local(2024, 4, 1, 0, 0))).to eq(1)
      end
    end
  end
end
