# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::RateCards::CycleWalker do
  subject(:walker) do
    described_class.new(
      anchor_date: Date.new(2026, 1, 31), starts_at:,
      phases:, rates:, timezone:, ends_at:
    )
  end

  let(:ends_at) { nil }
  let(:starts_at) { Time.utc(2026, 1, 31) }
  let(:timezone) { "UTC" }
  let(:phases) { [Billing::Phase.default] }
  let(:rates) { [rate] }
  let(:rate) do
    Struct.new(:effective_from, :billing_interval_count, :billing_interval_unit)
      .new(Time.utc(2026, 1, 1), 1, :month)
  end

  context "when several rates are scheduled after the card starts" do
    subject(:walker) do
      described_class.new(
        anchor_date: Date.new(2026, 1, 1), starts_at: Time.utc(2026, 1, 1),
        phases:, rates:, timezone:
      )
    end

    let(:rates) do
      [rate.class.new(Time.utc(2026, 6, 1), 1, :week),
        rate.class.new(Time.utc(2026, 9, 1), 1, :month)]
    end

    it "uses the earliest rate's cadence before pricing starts" do
      cycles = walker.walk_to(Time.utc(2026, 3, 1))

      expect(cycles.first(3).map { |cycle| [cycle.started_at, cycle.ended_at] }).to eq(
        [[Time.utc(2026, 1, 1), Time.utc(2026, 1, 8)],
          [Time.utc(2026, 1, 8), Time.utc(2026, 1, 15)],
          [Time.utc(2026, 1, 15), Time.utc(2026, 1, 22)]]
      )
      expect(cycles.map(&:index)).to eq((0..8).to_a)
    end
  end

  describe "#start" do
    it "opens cycle zero on the anchor's month-end grid" do
      cycle = walker.start

      expect([cycle.index, cycle.started_at, cycle.ended_at])
        .to eq([0, Time.utc(2026, 1, 31), Time.utc(2026, 2, 28)])
      expect(walker.current_cycle).to eq(cycle)
    end

    context "when the card starts inside a calendar interval" do
      let(:starts_at) { Time.utc(2026, 2, 10, 14, 30) }

      it "starts on the card's first billing day and keeps the next anchor boundary" do
        cycle = walker.start

        expect([cycle.started_at, cycle.ended_at]).to eq([Time.utc(2026, 2, 10), Time.utc(2026, 2, 28)])
      end
    end

    context "when the card ends during its first cycle" do
      let(:ends_at) { Time.utc(2026, 2, 15, 12) }

      it "clips the cycle to the actual end of service" do
        expect(walker.start.ended_at).to eq(ends_at)
      end
    end

    context "when the customer is west of UTC" do
      let(:starts_at) { Time.utc(2026, 2, 1, 2) }
      let(:timezone) { "America/New_York" }

      it "uses the local signing day and local calendar boundaries" do
        cycle = walker.start

        expect([cycle.started_at, cycle.ended_at]).to eq([Time.utc(2026, 1, 31, 5), Time.utc(2026, 2, 28, 5)])
      end
    end

    context "when the first phase overrides the interval unit" do
      let(:phases) do
        override = Struct.new(:billing_interval_count, :billing_interval_unit).new(nil, :week)
        [Billing::Phase.new(code: "intro", billing_interval_cycle_count: 2, rate_override: override), Billing::Phase.default]
      end

      it "uses the phase's unit and the rate's interval count" do
        expect(walker.start.ended_at).to eq(Time.utc(2026, 2, 7))
      end
    end

    context "when the card has rates before and after the one in force" do
      let(:rates) do
        previous = rate.class.new(Time.utc(2025, 12, 1), 1, :week)
        upcoming = rate.class.new(Time.utc(2026, 2, 1), 1, :year)
        [upcoming, previous, rate]
      end

      it "uses the interval of the rate effective on the first billing day" do
        expect(walker.start.ended_at).to eq(Time.utc(2026, 2, 28))
      end
    end
  end

  describe "#advance" do
    it "returns nil before the walker has started" do
      expect(walker.advance).to be_nil
    end

    it "continues from the previous cycle's end and preserves the month-end anchor" do
      walker.start
      cycle = walker.advance

      expect([cycle.index, cycle.started_at, cycle.ended_at])
        .to eq([1, Time.utc(2026, 2, 28), Time.utc(2026, 3, 31)])
      expect(walker.current_cycle).to eq(cycle)
      expect(walker.advance.ended_at).to eq(Time.utc(2026, 4, 30))
    end

    context "when the rate changes inside a cycle" do
      let(:rates) { [rate, rate.class.new(Time.utc(2026, 2, 15), 1, :week)] }

      it "applies the new interval from the next cycle's start" do
        expect(walker.start.ended_at).to eq(Time.utc(2026, 2, 28))

        cycle = walker.advance

        expect([cycle.started_at, cycle.ended_at]).to eq([Time.utc(2026, 2, 28), Time.utc(2026, 3, 7)])
      end
    end

    context "when the rate changes on a cycle boundary without changing the interval" do
      let(:rates) { [rate, rate.class.new(Time.utc(2026, 2, 28), 1, :month)] }

      it "keeps the original month-end anchor" do
        walker.start

        expect(walker.advance.ended_at).to eq(Time.utc(2026, 3, 31))
      end
    end

    context "when a weekly intro phase ends" do
      let(:phases) do
        override = Struct.new(:billing_interval_count, :billing_interval_unit).new(nil, :week)
        [Billing::Phase.new(code: "intro", billing_interval_cycle_count: 2, rate_override: override), Billing::Phase.default]
      end

      it "counts the intro cycles and starts the monthly calendar where the intro ends" do
        walker.start
        second_cycle = walker.advance
        monthly_cycle = walker.advance

        expect([second_cycle.index, second_cycle.ended_at, second_cycle.phase.code])
          .to eq([1, Time.utc(2026, 2, 14), "intro"])
        expect([monthly_cycle.index, monthly_cycle.started_at, monthly_cycle.ended_at, monthly_cycle.phase])
          .to eq([2, Time.utc(2026, 2, 14), Time.utc(2026, 3, 14), phases.last])
        expect(walker.advance.ended_at).to eq(Time.utc(2026, 4, 14))
      end
    end

    context "when the phase changes without changing the interval" do
      let(:phases) do
        [Billing::Phase.new(code: "intro", billing_interval_cycle_count: 1, rate_override: nil), Billing::Phase.default]
      end

      it "changes the phase and keeps the original month-end anchor" do
        walker.start
        cycle = walker.advance

        expect([cycle.phase, cycle.ended_at]).to eq([phases.last, Time.utc(2026, 3, 31)])
      end
    end

    context "when the card ends inside the next cycle" do
      let(:ends_at) { Time.utc(2026, 3, 15, 12) }

      it "clips the last cycle and stays exhausted until explicitly restarted" do
        walker.start

        expect(walker.advance.ended_at).to eq(ends_at)
        expect(walker.advance).to be_nil
        expect(walker.current_cycle).to be_nil
        expect(walker.advance).to be_nil
        expect(walker.start.index).to eq(0)
      end
    end

    context "when the card ends on a cycle boundary" do
      let(:ends_at) { Time.utc(2026, 2, 28) }

      it "stops without creating an empty cycle" do
        walker.start

        expect(walker.advance).to be_nil
        expect(walker.current_cycle).to be_nil
      end
    end

    context "when daylight saving time starts" do
      let(:timezone) { "America/New_York" }
      let(:starts_at) { Time.utc(2026, 1, 31, 5) }

      it "keeps the boundaries at local midnight" do
        walker.start
        cycle = walker.advance

        expect([cycle.started_at, cycle.ended_at]).to eq([Time.utc(2026, 2, 28, 5), Time.utc(2026, 3, 31, 4)])
      end
    end
  end

  describe "#resume" do
    it "reuses calculated boundaries when resuming again on the same calendar" do
      allow(Billing::Calendar).to receive(:new).and_call_original

      first = walker.resume(Time.utc(2026, 3, 15))
      repeated = walker.resume(Time.utc(2026, 3, 15))

      expect(repeated.calendar).to equal(first.calendar)
      expect([repeated.index, repeated.started_at, repeated.ended_at])
        .to eq([first.index, first.started_at, first.ended_at])
      expect(Billing::Calendar).to have_received(:new).once
    end

    it "jumps across a long history without building the intermediate cycles" do
      allow(Billing::Cycle).to receive(:new).and_call_original

      cycle = walker.resume(Time.utc(2126, 3, 15))

      expect([cycle.index, cycle.started_at, cycle.ended_at])
        .to eq([1201, Time.utc(2126, 2, 28), Time.utc(2126, 3, 31)])
      expect(Billing::Cycle).to have_received(:new).twice
    end

    it "selects the cycle opening exactly at the requested time" do
      cycle = walker.resume(Time.utc(2026, 3, 31))

      expect([cycle.index, cycle.started_at]).to eq([2, Time.utc(2026, 3, 31)])
    end

    it "starts at the first cycle when the requested time precedes the card" do
      cycle = walker.resume(Time.utc(2025, 1, 1))

      expect([cycle.index, cycle.started_at]).to eq([0, starts_at])
    end

    context "when the first cycle starts inside a calendar interval" do
      let(:starts_at) { Time.utc(2026, 2, 10) }

      it "counts the partial first cycle once and preserves the original anchor" do
        cycle = walker.resume(Time.utc(2026, 4, 10))

        expect([cycle.index, cycle.started_at, cycle.ended_at])
          .to eq([2, Time.utc(2026, 3, 31), Time.utc(2026, 4, 30)])
      end
    end

    context "when a rate changes the interval during the skipped history" do
      let(:rates) { [rate, rate.class.new(Time.utc(2026, 7, 15), 1, :week)] }

      it "jumps straight to the change without building the preceding cycle" do
        allow(Billing::Cycle).to receive(:new).and_call_original

        cycle = walker.resume(Time.utc(2026, 7, 31))

        expect([cycle.index, cycle.started_at, cycle.ended_at])
          .to eq([6, Time.utc(2026, 7, 31), Time.utc(2026, 8, 7)])
        expect(Billing::Cycle).to have_received(:new).twice
      end
    end

    context "when a phase overrides only the interval unit" do
      let(:rates) { [rate, rate.class.new(Time.utc(2026, 2, 5), 2, :month)] }
      let(:phases) do
        override = Struct.new(:billing_interval_count, :billing_interval_unit).new(nil, :week)
        [Billing::Phase.new(code: "intro", billing_interval_cycle_count: 3, rate_override: override), Billing::Phase.default]
      end

      it "combines the override with the new rate and removes it when the phase ends" do
        intro_cycle = walker.resume(Time.utc(2026, 2, 10))
        regular_cycle = walker.resume(Time.utc(2026, 3, 10))

        expect([intro_cycle.index, intro_cycle.started_at, intro_cycle.ended_at, intro_cycle.phase.code])
          .to eq([1, Time.utc(2026, 2, 7), Time.utc(2026, 2, 21), "intro"])
        expect([regular_cycle.index, regular_cycle.started_at, regular_cycle.ended_at, regular_cycle.phase])
          .to eq([3, Time.utc(2026, 3, 7), Time.utc(2026, 5, 7), phases.last])
      end
    end

    context "when phases and rates change during the skipped history" do
      let(:rates) do
        [rate,
          rate.class.new(Time.utc(2026, 2, 15), 2, :month),
          rate.class.new(Time.utc(2026, 2, 20), 3, :month),
          rate.class.new(Time.utc(2026, 5, 28), 1, :week),
          rate.class.new(Time.utc(2026, 7, 1), 1, :month)]
      end
      let(:phases) do
        override = Struct.new(:billing_interval_count, :billing_interval_unit).new(1, :month)
        [Billing::Phase.new(code: "intro", billing_interval_cycle_count: 3, rate_override: override),
          Billing::Phase.new(code: "discount", billing_interval_cycle_count: 2, rate_override: nil),
          Billing::Phase.default]
      end

      it "matches a full walk inside cycles and on every cycle boundary" do
        cycles = walker.walk_to(Time.utc(2027, 1, 1))

        cycles.each do |expected|
          [expected.started_at, expected.started_at + 1.hour].each do |timestamp|
            actual = walker.resume(timestamp)

            expect([actual.index, actual.started_at, actual.ended_at, actual.phase])
              .to eq([expected.index, expected.started_at, expected.ended_at, expected.phase])
            expect([actual.calendar.anchor_date, actual.calendar.interval])
              .to eq([expected.calendar.anchor_date, expected.calendar.interval])
          end
        end
      end

      it "reuses each calendar without mixing intervals or realigned anchors" do
        first_walk = walker.walk_to(Time.utc(2027, 1, 1))
        calendars = first_walk.map(&:calendar).uniq
        allow(Billing::Calendar).to receive(:new).and_call_original

        repeated_walk = walker.walk_to(Time.utc(2027, 1, 1))

        expect(repeated_walk.map(&:calendar)).to eq(first_walk.map(&:calendar))
        expect(calendars.select { |calendar| calendar.interval == calendars.first.interval }.map(&:anchor_date).uniq.size)
          .to be > 1
        expect(Billing::Calendar).not_to have_received(:new)
      end
    end

    context "when the first rate takes effect after the card starts" do
      let(:rates) do
        [rate.class.new(Time.utc(2026, 3, 15), 1, :month),
          rate.class.new(Time.utc(2026, 5, 15), 1, :week)]
      end

      it "counts the unpriced cycles and matches a full walk across the interval change" do
        expected = walker.walk_to(Time.utc(2026, 6, 10)).last
        actual = walker.resume(Time.utc(2026, 6, 10))

        expect([actual.index, actual.started_at, actual.ended_at])
          .to eq([expected.index, expected.started_at, expected.ended_at])
      end
    end

    context "when a daily calendar crosses daylight saving time" do
      let(:timezone) { "America/New_York" }
      let(:starts_at) { Time.utc(2026, 1, 31, 5) }
      let(:rates) { [rate.class.new(Time.utc(2026, 1, 1), 1, :day)] }

      it "skips local days and keeps midnight boundaries" do
        cycle = walker.resume(Time.utc(2026, 3, 10, 12))

        expect([cycle.index, cycle.started_at, cycle.ended_at])
          .to eq([38, Time.utc(2026, 3, 10, 4), Time.utc(2026, 3, 11, 4)])
      end
    end

    context "when the requested time is after termination" do
      let(:ends_at) { Time.utc(2026, 3, 15) }

      it "leaves the walker exhausted" do
        expect(walker.resume(Time.utc(2026, 4, 1))).to be_nil
        expect(walker.current_cycle).to be_nil
      end
    end
  end

  describe "#walk_to" do
    it "returns the completed cycles and the cycle containing the requested time" do
      cycles = walker.walk_to(Time.utc(2026, 4, 10))

      expect(cycles.map { |cycle| [cycle.index, cycle.started_at, cycle.ended_at] }).to eq([
        [0, Time.utc(2026, 1, 31), Time.utc(2026, 2, 28)],
        [1, Time.utc(2026, 2, 28), Time.utc(2026, 3, 31)],
        [2, Time.utc(2026, 3, 31), Time.utc(2026, 4, 30)]
      ])
      expect(walker.current_cycle).to eq(cycles.last)
      expect(walker.advance.started_at).to eq(Time.utc(2026, 4, 30))
    end

    it "includes the cycle opening exactly at the requested time" do
      cycles = walker.walk_to(Time.utc(2026, 2, 28))

      expect(cycles.map(&:index)).to eq([0, 1])
      expect(cycles.last.started_at).to eq(Time.utc(2026, 2, 28))
    end

    it "returns no cycles before the card starts" do
      expect(walker.walk_to(Time.utc(2026, 1, 30))).to be_empty
    end

    it "includes the first cycle at the card's start" do
      expect(walker.walk_to(starts_at).map(&:index)).to eq([0])
    end

    it "starts a fresh walk regardless of the previous position" do
      walker.walk_to(Time.utc(2026, 4, 10))

      expect(walker.walk_to(Time.utc(2026, 3, 10)).map(&:index)).to eq([0, 1])
      expect(walker.walk_to(Time.utc(2026, 4, 10)).map(&:index)).to eq([0, 1, 2])
    end

    context "when the card ends before the requested time" do
      let(:ends_at) { Time.utc(2026, 3, 15, 12) }

      it "returns all cycles through termination and stops" do
        cycles = walker.walk_to(Time.utc(2026, 4, 10))

        expect(cycles.map(&:index)).to eq([0, 1])
        expect(cycles.last.ended_at).to eq(ends_at)
        expect(walker.current_cycle).to be_nil
      end
    end

    context "when the card ends at its start" do
      let(:ends_at) { starts_at }

      it "returns no cycles" do
        expect(walker.walk_to(starts_at)).to be_empty
      end
    end
  end

  it "resumes inside a cycle and preserves the month-end anchor when advancing" do
    expect(walker.resume(Time.utc(2026, 2, 10)).started_at).to eq(Time.utc(2026, 1, 31))
    expect(walker.advance.ended_at).to eq(Time.utc(2026, 3, 31))
    expect(walker.current_cycle.index).to eq(1)
  end

  it "can resume backwards after advancing" do
    walker.resume(Time.utc(2026, 4, 1))
    walker.advance

    cycle = walker.resume(Time.utc(2026, 2, 10))

    expect([cycle.index, cycle.started_at, cycle.ended_at])
      .to eq([0, Time.utc(2026, 1, 31), Time.utc(2026, 2, 28)])
  end

  it "starts each walk at its explicit from date regardless of the current position" do
    timestamp = Time.utc(2026, 4, 30)
    walker.resume(Time.utc(2026, 4, 1))
    walker.advance

    expect(walker.walk_to(timestamp, from: nil).map(&:index)).to eq([0, 1, 2, 3])
    expect(walker.walk_to(timestamp, from: Time.utc(2026, 3, 31)).map(&:index)).to eq([2, 3])
    expect(walker.advance.index).to eq(4)
  end

  it "can explicitly return to the beginning after advancing" do
    walker.resume(Time.utc(2026, 4, 1))
    walker.advance

    expect(walker.resume(nil).index).to eq(0)
    expect(walker.advance.index).to eq(1)
  end

  context "when the card ends inside a cycle" do
    let(:ends_at) { Time.utc(2026, 4, 15) }

    it "stops at termination and can subsequently resume an earlier cycle" do
      expect(walker.resume(Time.utc(2026, 4, 1)).ended_at).to eq(ends_at)
      expect(walker.advance).to be_nil
      expect(walker.advance).to be_nil
      expect(walker.resume(ends_at)).to be_nil
      expect(walker.current_cycle).to be_nil
      expect(walker.resume(Time.utc(2026, 2, 1)).index).to eq(0)
    end
  end
end
