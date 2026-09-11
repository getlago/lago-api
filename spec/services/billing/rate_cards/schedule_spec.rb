# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::RateCards::Schedule do
  subject(:schedule) do
    described_class.new(anchor_date:, phases:, rates:, terms:, timezone:, starts_at:, ends_at:)
  end

  let(:anchor_date) { Date.new(2022, 1, 1) }
  let(:phases) { [phase(cycle_count: nil, every: 1, unit: :month)] }
  let(:rates) { [card_rate(Time.utc(2000, 1, 1))] }
  let(:prorated) { true }
  let(:timezone) { "UTC" }
  let(:starts_at) { Time.utc(2022, 1, 15) }
  let(:timing) { :arrears }
  let(:ends_at) { nil }
  let(:terms) { Billing::Terms.new(timing:, prorated:) }

  # The two shapes the schedule reads. A rate carries the cadence and the date it takes
  # effect; an override pins the cadence for one phase and wins over the rate, which is how
  # production configures a phase that bills on its own rhythm.
  def card_rate(effective_from, count = 1, unit = :month)
    Struct.new(:effective_from, :billing_interval_count, :billing_interval_unit)
      .new(effective_from, count, unit)
  end

  def interval_override(count, unit, label)
    Struct.new(:billing_interval_count, :billing_interval_unit, :label).new(count, unit, label)
  end

  # The phases are handed in the order they bill. The schedule does not re-sort them: both
  # associations that produce them are `order(:position)`, so the order is the producer's
  # contract and Schedule#validate! asserts it rather than repairing it.
  def phase(cycle_count:, every:, unit:, code: "standard", override: nil)
    Billing::Phase.new(
      code:,
      billing_interval_cycle_count: cycle_count,
      rate_override: interval_override(every, unit, override)
    )
  end

  # The plan shows bounds inclusive, so the exclusive end reads as the day before.
  def windows(cycles)
    cycles.map { |cycle| "#{cycle.started_at.to_date} -> #{(cycle.ended_at - 1.day).to_date}" }
  end

  describe "validation" do
    # Without a rate the walk breaks before producing anything and answers "no cycles", which
    # reads as a card that never bills rather than as a card built wrong. BuildScheduleService
    # already fails its result on this; a schedule built directly must not stay silent.
    it "rejects a schedule with no rates" do
      expect { described_class.new(anchor_date:, phases:, rates: [], terms:, timezone:, starts_at:, ends_at:) }
        .to raise_error(ArgumentError, /at least one rate/)
    end

    it "rejects an end before the start" do
      expect { described_class.new(anchor_date:, phases:, rates:, terms:, timezone:, starts_at:, ends_at: starts_at - 1.day) }
        .to raise_error(ArgumentError, /precedes starts_at/)
    end

    it "rejects an empty phase list" do
      expect { described_class.new(anchor_date:, phases: [], rates:, terms:, timezone:, starts_at:) }
        .to raise_error(ArgumentError, /at least one phase/)
    end

    # A bounded last phase stops producing cycles while the card is still live, which
    # downstream reads as nothing being due rather than as an error.
    it "rejects a bounded last phase" do
      broken = [phase(cycle_count: 6, every: 1, unit: :month)]

      expect { described_class.new(anchor_date:, phases: broken, rates:, terms:, timezone:, starts_at:) }
        .to raise_error(ArgumentError, /last phase must run to the end/)
    end

    it "rejects an open phase that is not the last" do
      broken = [phase(cycle_count: nil, every: 1, unit: :week), phase(cycle_count: nil, every: 1, unit: :month)]

      expect { described_class.new(anchor_date:, phases: broken, rates:, terms:, timezone:, starts_at:) }
        .to raise_error(ArgumentError, /only the last phase/)
    end
  end

  describe "cycle information on billable segments" do
    it "clamps the first cycle to the start rather than to the boundary before it" do
      expect(windows(schedule.segments_due_by(Time.utc(2022, 3, 1))))
        .to eq(["2022-01-15 -> 2022-01-31", "2022-02-01 -> 2022-02-28"])
    end

    # A cycle running over the timestamp but closing after it has not fallen due yet.
    it "leaves out a cycle that has not closed by the timestamp" do
      expect(windows(schedule.segments_due_by(Time.utc(2022, 2, 10)))).to eq(["2022-01-15 -> 2022-01-31"])
    end

    # The last one closes exactly on the timestamp asked about, so it has fallen due.
    it "numbers cycles from zero, counting from the card start" do
      expect(schedule.segments_due_by(Time.utc(2022, 5, 1)).map(&:cycle_index)).to eq([0, 1, 2, 3])
    end

    it "returns nothing when nothing has fallen due" do
      expect(schedule.segments_due_by(starts_at)).to be_empty
    end

    context "when the card bills in advance" do
      let(:timing) { :advance }

      it "includes the first cycle as soon as it starts" do
        expect(schedule.segments_due_by(starts_at).map(&:cycle_index)).to eq([0])
      end

      it "includes the cycle opening exactly at the requested time" do
        expect(schedule.segments_due_by(Time.utc(2022, 2, 1)).map(&:cycle_index)).to eq([0, 1])
      end
    end

    context "when the card starts before the anchor" do
      let(:starts_at) { Time.utc(2021, 12, 20) }

      it "still opens at cycle 0, clamped to the start" do
        cycle = schedule.segments_due_by(Time.utc(2022, 1, 1)).sole

        expect(cycle.cycle_index).to eq(0)
        expect(cycle.started_at...cycle.ended_at).to eq(Time.utc(2021, 12, 20)...Time.utc(2022, 1, 1))
      end
    end

    context "when the schedule ends" do
      let(:ends_at) { Time.utc(2022, 3, 20) }

      it "clamps the final cycle to the end and stops there" do
        expect(windows(schedule.segments_due_by(Time.utc(2023, 1, 1))))
          .to eq(["2022-01-15 -> 2022-01-31", "2022-02-01 -> 2022-02-28", "2022-03-01 -> 2022-03-19"])
      end

      context "when the end falls exactly on a boundary" do
        let(:ends_at) { Time.utc(2022, 3, 1) }

        it "stops without emitting an empty cycle" do
          expect(windows(schedule.segments_due_by(Time.utc(2023, 1, 1))))
            .to eq(["2022-01-15 -> 2022-01-31", "2022-02-01 -> 2022-02-28"])
        end
      end
    end
  end

  describe "an initial billing bound on a shortened schedule" do
    let(:ends_at) { Time.utc(2022, 1, 25, 12) }

    it "includes the final arrears segment when the clock still points to its original end" do
      segment = schedule.segments_due_by(Time.utc(2022, 2, 1), billing_from: Time.utc(2022, 2, 1)).sole

      expect(segment.started_at).to eq(starts_at)
      expect(segment.ended_at).to eq(ends_at)
      expect(segment.billing_at).to eq(ends_at)
      expect(segment.proration_ratio).to eq(11.fdiv(31))
    end

    it "does not resurrect historical cycles before the initial billing bound" do
      expect(schedule.segments_due_by(Time.utc(2022, 4, 1), billing_from: Time.utc(2022, 4, 1))).to eq([])
    end

    context "with a price change inside the final cycle" do
      let(:rates) { [card_rate(Time.utc(2000, 1, 1)), card_rate(Time.utc(2022, 1, 20))] }

      it "keeps the bound at the pricing segment rather than reopening the entire cycle" do
        segments = schedule.segments_due_by(Time.utc(2022, 2, 1), billing_from: Time.utc(2022, 2, 1))

        expect(segments.map(&:started_at)).to eq([Time.utc(2022, 1, 20)])
        expect(segments.sole.ended_at).to eq(ends_at)
      end
    end
  end

  describe "when a window falls due" do
    it "bills at the end of the cycle in arrears" do
      expect(schedule.segments_due_by(Time.utc(2022, 4, 1)).map(&:billing_at))
        .to eq([Time.utc(2022, 2, 1), Time.utc(2022, 3, 1), Time.utc(2022, 4, 1)])
    end

    context "when the card bills in advance" do
      let(:timing) { :advance }

      it "bills at the start of the cycle" do
        expect(schedule.segments_due_by(Time.utc(2022, 4, 1)).map(&:billing_at))
          .to eq([Time.utc(2022, 1, 15), Time.utc(2022, 2, 1), Time.utc(2022, 3, 1), Time.utc(2022, 4, 1)])
      end
    end

    context "when a termination cuts the cycle short" do
      let(:ends_at) { Time.utc(2022, 3, 20) }

      it "bills the final cycle at the termination, not at the boundary" do
        expect(schedule.segments_due_by(Time.utc(2023, 1, 1)).last.billing_at).to eq(Time.utc(2022, 3, 20))
      end
    end
  end

  # The flat shape the consumer lane writes rows from: one entry per slice, cycle facts
  # already joined, so a writer never has to hold two objects to fill one row.
  describe "the flat segment surface" do
    let(:cut) { Time.utc(2022, 2, 15) }
    let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(cut)] }

    describe "#segments_due_by" do
      # The bug this fixes, and the reason the release gate cannot live on the cycle: the
      # February cycle is cut on the 15th, so its first slice falls due THAT DAY. Gating on
      # the cycle's own due instant (Mar 1) withheld it, and for an arrears card whose clock
      # had already moved past the 15th, withheld it for good. QA plan R3b, decision #60 —
      # one document per transition.
      it "releases the slice before a cut as soon as the cut passes, not when the cycle closes" do
        due = schedule.segments_due_by(Time.utc(2022, 2, 20))

        expect(due.map { |segment| [segment.started_at.to_date.to_s, segment.billing_at.to_date.to_s] }).to eq(
          [["2022-01-15", "2022-02-01"],
            ["2022-02-01", "2022-02-15"]]
        )
      end

      it "still withholds the slice after the cut until its own boundary" do
        expect(schedule.segments_due_by(Time.utc(2022, 2, 20)).map(&:ended_at))
          .not_to include(Time.utc(2022, 3, 1))
      end

      it "joins the cycle's facts onto every slice" do
        first, second = schedule.segments_due_by(Time.utc(2022, 2, 20)).last(2)

        expect([first.cycle_index, second.cycle_index]).to eq([0, 1])
        expect(second.cycle_started_at).to eq(Time.utc(2022, 2, 1))
      end

      # The two slices of one cut cycle are shares of that cycle, so they add back up to it.
      it "prorates each slice against its own cycle" do
        ratios = schedule.segments_due_by(Time.utc(2022, 4, 1))
          .select { |segment| segment.cycle_index == 1 }
          .map(&:proration_ratio)

        expect(ratios).to eq([14.fdiv(28), 14.fdiv(28)])
        expect(ratios.sum).to eq(1.0)
      end

      context "when the card bills in advance" do
        let(:timing) { :advance }

        it "releases each segment when it starts, including at a rate change" do
          segments = schedule.segments_due_by(cut)

          expect(segments.map { |segment| [segment.started_at, segment.billing_at] }).to eq([
            [Time.utc(2022, 1, 15), Time.utc(2022, 1, 15)],
            [Time.utc(2022, 2, 1), Time.utc(2022, 2, 1)],
            [cut, cut]
          ])
        end
      end

      context "when the first rate starts inside a cycle" do
        let(:rates) { [card_rate(cut)] }

        it "does not return the unpriced segments before the first rate" do
          expect(schedule.segments_due_by(cut)).to be_empty
        end

        it "returns only the priced part when it falls due" do
          segment = schedule.segments_due_by(Time.utc(2022, 3, 1)).sole

          expect([segment.cycle_index, segment.started_at, segment.ended_at, segment.billing_at, segment.rate])
            .to eq([1, cut, Time.utc(2022, 3, 1), Time.utc(2022, 3, 1), rates.sole])
          expect(segment.proration_ratio).to eq(0.5)
        end
      end

      context "when proration is disabled" do
        let(:prorated) { false }

        it "gives each priced segment a full ratio" do
          segments = schedule.segments_due_by(Time.utc(2022, 3, 1)).select { |segment| segment.cycle_index == 1 }

          expect(segments.map(&:proration_ratio)).to eq([1.0, 1.0])
        end
      end
    end

    describe "#consumed_ratio" do
      subject(:segment) do
        schedule.segments_due_by(Date.new(2022, 3, 1).in_time_zone(timezone))
          .find { |candidate| candidate.started_at == cut }
      end

      # A share of the SEGMENT, never of the cycle. Measuring elapsed segment days against
      # the whole cycle refunds days the slice before the rate change already paid for.
      it "measures elapsed segment days against billed segment days" do
        expect(schedule.consumed_ratio(segment:, at: Time.utc(2022, 2, 22))).to eq(7.fdiv(14))
      end

      it "is nothing consumed at the segment's own start" do
        expect(schedule.consumed_ratio(segment:, at: segment.started_at)).to eq(0.0)
      end

      it "is nothing consumed before the segment starts" do
        expect(schedule.consumed_ratio(segment:, at: segment.started_at - 1.day)).to eq(0.0)
      end

      it "is fully consumed at its end" do
        expect(schedule.consumed_ratio(segment:, at: segment.ended_at)).to eq(1.0)
      end

      it "is fully consumed after its end" do
        expect(schedule.consumed_ratio(segment:, at: segment.ended_at + 1.day)).to eq(1.0)
      end

      context "when the customer is west of UTC" do
        let(:timezone) { "America/New_York" }
        let(:cut) { Time.utc(2022, 2, 15, 5) }

        it "counts the day in progress in the customer's timezone" do
          expect(schedule.consumed_ratio(segment:, at: Time.utc(2022, 2, 22, 12))).to eq(8.fdiv(14))
        end
      end

      # QA plan X2, through the path production actually takes: the credit for an unused
      # pay-in-advance interval is `1 - consumed_ratio`, measured to the instant
      # Days hands back. It was previously asserted against a formula written in
      # the spec file, which meant neither of the two methods below had to be right.
      context "with the X2 termination scenario" do
        subject(:segment) do
          advance_schedule.segments_due_by(Time.utc(2026, 9, 15)).sole
        end

        let(:advance_schedule) do
          described_class.new(
            anchor_date: Date.new(2026, 9, 10),
            phases: [phase(cycle_count: nil, every: 1, unit: :month)],
            rates: [card_rate(Time.utc(2026, 1, 1))],
            terms: Billing::Terms.new(timing: :advance, prorated: true),
            timezone: "UTC",
            starts_at: Time.utc(2026, 9, 10),
            ends_at: nil
          )
        end

        # A 30-day window Sep 10 -> Oct 9 paid at 150.00, terminated on Sep 25. The
        # termination day is consumed, so 14 unused days are worth 70.00.
        it "credits the fourteen unused days" do
          unused = 1 - advance_schedule.consumed_ratio(segment:, at: Time.utc(2026, 9, 25, 16, 30))

          expect(unused).to eq(14.fdiv(30))
          expect((unused * 150_00).round).to eq(70_00)
        end

        # QA plan X1: the termination day is inclusive, so the hour it happens at must not
        # move the credit. Terminating at midnight used to credit a day more than
        # terminating the same afternoon.
        it "credits the same whatever hour the termination lands at" do
          # Any hour AFTER midnight answers alike, because the day-ownership rule gives the
          # day it lands in whole. Midnight itself is the one instant that differs, and it is
          # a termination with no service in that day at all.
          credits = [Time.utc(2026, 9, 25, 0, 0, 1), Time.utc(2026, 9, 25, 12, 34, 56), Time.utc(2026, 9, 25, 23, 59, 59)]
            .map { |at| 1 - advance_schedule.consumed_ratio(segment:, at:) }

          expect(credits).to eq([14.fdiv(30)] * 3)

          expect(1 - advance_schedule.consumed_ratio(segment:, at: Time.utc(2026, 9, 25)))
            .to eq(15.fdiv(30))
        end

        it "credits nothing when the termination lands on the closing boundary" do
          expect(1 - advance_schedule.consumed_ratio(segment:, at: Time.utc(2026, 10, 9, 23))).to eq(0.0)
        end
      end

      # Billing::Days counts day OPENINGS, so a slice that opens and closes inside one local
      # day covers none — it was charged nothing, and 0/0 would put a NaN into a credit note.
      # A NaN is worse than a wrong number here: it compares false against every threshold,
      # so a caller's clamp passes it straight through.
      context "when a slice opens and closes inside one day" do
        subject(:segment) do
          schedule.segments_due_by(Time.utc(2022, 4, 1))
            .find { |candidate| candidate.started_at == Time.utc(2022, 2, 15, 9) }
        end

        let(:rates) do
          [card_rate(Time.utc(2021, 1, 1)),
            card_rate(Time.utc(2022, 2, 15, 9)),
            card_rate(Time.utc(2022, 2, 15, 18))]
        end

        it "is a real number, never NaN" do
          ratio = schedule.consumed_ratio(segment:, at: Time.utc(2022, 2, 15, 12))

          expect(ratio).to be_a(Float)
          expect(ratio).not_to be_nan
        end

        it "has nothing left to credit, because it was charged nothing" do
          expect(segment.proration_ratio).to eq(0.0)
          expect(schedule.consumed_ratio(segment:, at: Time.utc(2022, 2, 15, 12))).to eq(1.0)
        end
      end
    end
  end

  # The cut and the share, read where the consumer reads them. The cycle carries the ruler it
  # was measured on and nothing else: what a window costs needs the card's terms, so the
  # schedule answers that, not the cycle.
  describe "cutting a cycle and sharing it" do
    subject(:slices) do
      schedule.segments_due_by(Time.utc(2022, 4, 1))
        .select { |segment| segment.cycle_started_at == Time.utc(2022, 3, 1) }
    end

    def bounds = slices.map { |slice| [slice.started_at, slice.ended_at] }

    def ratios = slices.map(&:proration_ratio)

    it "is the whole cycle when no rate changes inside it" do
      expect(bounds).to eq([[Time.utc(2022, 3, 1), Time.utc(2022, 4, 1)]])
      expect(ratios).to eq([1.0])
    end

    context "when a rate change lands part-way through" do
      let(:change) { Time.utc(2022, 3, 15) }
      let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(change)] }

      it "splits at the change" do
        expect(bounds).to eq([[Time.utc(2022, 3, 1), change], [change, Time.utc(2022, 4, 1)]])
      end
    end

    # The two sides of a rate change have to add up to one interval, whatever hour the
    # change lands at — the day-ownership rule Billing::Days exists to keep.
    context "when a rate change lands mid-day inside the cycle" do
      let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(Time.utc(2022, 3, 15, 14))] }

      it "shares one interval between the segments of a cut cycle" do
        expect(ratios).to eq([15.fdiv(31), 16.fdiv(31)])
        expect(ratios.sum).to eq(1.0)
      end
    end

    # A termination clamps the cycle, so it bills the share it actually ran.
    context "when the schedule ends part-way through the cycle" do
      let(:ends_at) { Time.utc(2022, 3, 20) }

      it "prorates the clamped cycle" do
        expect(ratios).to eq([19.fdiv(31)])
      end
    end

    # An unprorated card pays the full price for whatever it got: the clamp changes what
    # the cycle covers, never what it costs. Without this the `prorated` flag could be
    # deleted outright and every other example here would still pass.
    context "when the card does not prorate" do
      let(:prorated) { false }
      let(:ends_at) { Time.utc(2022, 3, 20) }

      it "bills a clamped cycle whole" do
        expect(ratios).to eq([1.0])
      end

      context "when a rate change cuts the cycle as well" do
        let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(Time.utc(2022, 3, 10))] }

        it "bills each slice whole, so the cut cycle costs twice" do
          expect(ratios).to eq([1.0, 1.0])
        end
      end
    end

    # Both clamps at once, which no other example combines: the cycle is cut by a rate
    # change AND closed early by the termination. The slices must add up to the share the
    # card actually ran, not to a whole interval.
    context "when the cycle is both cut by a rate change and clamped by the end" do
      let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(Time.utc(2022, 3, 10))] }
      let(:ends_at) { Time.utc(2022, 3, 20) }

      it "shares the clamped run between the slices" do
        expect(ratios).to eq([9.fdiv(31), 10.fdiv(31)])
        expect(ratios.sum).to eq(19.fdiv(31))
      end
    end
  end

  # What seeds the clock. It counts a cycle already due but still
  # running, because nothing has billed it yet.
  # Two questions, two methods, and the names used to be one. #next_billing_at ADVANCES the
  # clock — strictly after, per segment; #billing_at_covering SEEDS it — the cycle being
  # served, even when it already fell due. The consumer lane calls the first from three
  # places with `after:`, and the second only at materialization.
  describe "#next_billing_at" do
    it "answers the first slice falling due strictly after the instant asked about" do
      expect(schedule.next_billing_at(after: starts_at)).to eq(Time.utc(2022, 2, 1))
    end

    it "skips the cycles that already closed" do
      expect(schedule.next_billing_at(after: Time.utc(2022, 3, 10))).to eq(Time.utc(2022, 4, 1))
    end

    it "skips billing exactly at the requested instant" do
      expect(schedule.next_billing_at(after: Time.utc(2022, 3, 1))).to eq(Time.utc(2022, 4, 1))
    end

    context "when asked before the card starts" do
      it "returns the end of the first priced segment in arrears" do
        expect(schedule.next_billing_at(after: Time.utc(2022, 1, 1))).to eq(Time.utc(2022, 2, 1))
      end

      context "when billing in advance" do
        let(:timing) { :advance }

        it "returns the card's start" do
          expect(schedule.next_billing_at(after: Time.utc(2022, 1, 1))).to eq(starts_at)
        end
      end
    end

    # A cut cycle owes the piece before the cut ON the cut. Answering with the cycle's own
    # due instant dragged that piece to the end of the cycle, and for a clock already past
    # it, lost it — a 15-day arrears segment, never billed.
    context "when a rate change cuts the cycle" do
      let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(Time.utc(2022, 2, 15))] }

      it "owes the cut, not the end of the cycle" do
        expect(schedule.next_billing_at(after: Time.utc(2022, 2, 1))).to eq(Time.utc(2022, 2, 15))
      end

      context "when billing in advance" do
        let(:timing) { :advance }

        it "finds the next segment in a cycle that is already due" do
          expect(schedule.next_billing_at(after: Time.utc(2022, 2, 10))).to eq(Time.utc(2022, 2, 15))
        end

        it "skips the segment starting exactly at the requested instant" do
          expect(schedule.next_billing_at(after: Time.utc(2022, 2, 15))).to eq(Time.utc(2022, 3, 1))
        end
      end
    end

    context "when pricing starts after several unpriced cycles" do
      let(:rates) { [card_rate(Time.utc(2022, 5, 1))] }

      it "finds the end of the first priced segment in arrears" do
        expect(schedule.next_billing_at(after: starts_at)).to eq(Time.utc(2022, 6, 1))
      end

      context "when billing in advance" do
        let(:timing) { :advance }

        it "finds the start of the first priced segment" do
          expect(schedule.next_billing_at(after: starts_at)).to eq(Time.utc(2022, 5, 1))
        end
      end

      context "when the card ends before pricing starts" do
        let(:ends_at) { Time.utc(2022, 4, 1) }

        it "reports nothing further" do
          expect(schedule.next_billing_at(after: starts_at)).to be_nil
        end
      end
    end

    # It used to bound its own walk by `after + 1.year`, which answered "nothing, ever
    # again" for any cadence longer than a year — and the consumer reads that answer as a
    # clock that never needs winding, so the card would never bill again.
    context "with a cadence longer than the bound a guess would have used" do
      let(:rates) { [card_rate(Time.utc(2021, 1, 1), 2, :year)] }
      let(:phases) { [phase(cycle_count: nil, every: 2, unit: :year)] }
      let(:anchor_date) { Date.new(2022, 1, 1) }
      let(:starts_at) { Time.utc(2022, 1, 1) }

      it "still finds the next slice" do
        expect(schedule.next_billing_at(after: Time.utc(2022, 1, 1))).to eq(Time.utc(2024, 1, 1))
      end
    end

    context "when the schedule has already ended" do
      let(:ends_at) { Time.utc(2022, 3, 1) }

      it "reports nothing further" do
        expect(schedule.next_billing_at(after: Time.utc(2023, 1, 1))).to be_nil
      end
    end
  end

  describe "#billing_at_covering" do
    # Every other example here asks at a NON-boundary instant, where the two readings agree.
    # Materialization asks exactly on the boundary on every rollover, and there `>=` returns
    # the cycle that just CLOSED — seeding the clock a whole period in the past and re-billing
    # a period already invoiced.
    it "answers the cycle a boundary opens, not the one it closes" do
      expect(schedule.billing_at_covering(Time.utc(2022, 3, 1))).to eq(Time.utc(2022, 4, 1))
    end

    it "waits for the first cycle to close in arrears" do
      expect(schedule.billing_at_covering(starts_at)).to eq(Time.utc(2022, 2, 1))
    end

    context "when a rate change splits the current cycle" do
      let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(Time.utc(2022, 2, 15))] }

      it "returns the current segment's end before the change" do
        expect(schedule.billing_at_covering(Time.utc(2022, 2, 10))).to eq(Time.utc(2022, 2, 15))
      end

      it "selects the new segment exactly at the change" do
        expect(schedule.billing_at_covering(Time.utc(2022, 2, 15))).to eq(Time.utc(2022, 3, 1))
      end

      context "when billing in advance" do
        let(:timing) { :advance }

        it "returns the current segment's start before the change" do
          expect(schedule.billing_at_covering(Time.utc(2022, 2, 10))).to eq(Time.utc(2022, 2, 1))
        end

        it "returns the new segment's start exactly at the change" do
          expect(schedule.billing_at_covering(Time.utc(2022, 2, 15))).to eq(Time.utc(2022, 2, 15))
        end

        it "keeps the current segment's billing date after the change" do
          expect(schedule.billing_at_covering(Time.utc(2022, 2, 20))).to eq(Time.utc(2022, 2, 15))
        end
      end
    end

    context "when pricing has not started" do
      let(:rates) { [card_rate(Time.utc(2022, 5, 1))] }

      it "waits for the first priced segment to end" do
        expect(schedule.billing_at_covering(starts_at)).to eq(Time.utc(2022, 6, 1))
      end

      context "when billing in advance" do
        let(:timing) { :advance }

        it "waits for the first priced segment to start" do
          expect(schedule.billing_at_covering(starts_at)).to eq(Time.utc(2022, 5, 1))
        end
      end

      context "when the card ends before pricing starts" do
        let(:ends_at) { Time.utc(2022, 4, 1) }

        it "has no billing date" do
          expect(schedule.billing_at_covering(starts_at)).to be_nil
        end
      end
    end

    context "when the card bills in advance" do
      let(:timing) { :advance }

      it "reports the cycle in force even though it is already due" do
        expect(schedule.billing_at_covering(starts_at)).to eq(starts_at)
      end

      # The cycle covering Mar 10 opened on Mar 1 and was never billed, so the clock owes
      # that rather than the cycle ahead.
      it "does not skip a due cycle that is still running" do
        expect(schedule.billing_at_covering(Time.utc(2022, 3, 10))).to eq(Time.utc(2022, 3, 1))
      end

      # The one case that separates the two methods, and the reason shipping them under one
      # name was a defect: seeding must answer the period being served, advancing must not.
      it "differs from #next_billing_at on the very cycle being served" do
        at = Time.utc(2022, 3, 10)

        expect(schedule.billing_at_covering(at)).to eq(Time.utc(2022, 3, 1))
        expect(schedule.next_billing_at(after: at)).to eq(Time.utc(2022, 4, 1))
      end
    end

    context "when the schedule has already ended" do
      let(:ends_at) { Time.utc(2022, 3, 1) }

      it "reports nothing further" do
        expect(schedule.billing_at_covering(Time.utc(2023, 1, 1))).to be_nil
      end

      it "has no segment covering the exclusive end" do
        expect(schedule.billing_at_covering(ends_at)).to be_nil
      end
    end
  end

  # The walk builds one ruler per (anchor, interval), not one per cycle. No assertion on the
  # cycles it returns can see the difference — 240 identical calendars produce the same
  # answer as one — so the count is asserted here directly.
  describe "calendar reuse" do
    let(:asked_at) { Time.utc(2032, 1, 1) }

    before { allow(Billing::Calendar).to receive(:new).and_call_original }

    it "builds one calendar however many cycles it walks" do
      expect(schedule.segments_due_by(asked_at).size).to eq(120)
      expect(Billing::Calendar).to have_received(:new).once
    end
  end

  # The worked example the PR description is built on, kept executable so the two cannot
  # drift. A monthly card with a three-cycle weekly intro phase, starting two days after its
  # anchor, with two rates taking effect inside cycles rather than on a boundary.
  describe "an intro phase with rate changes landing inside cycles" do
    subject(:schedule) { described_class.new(**arguments) }

    let(:arguments) do
      {
        anchor_date: Date.new(2026, 8, 10),
        starts_at: Time.utc(2026, 8, 12),
        rates:,
        terms: Billing::Terms.new(timing:, prorated: true),
        timezone: "UTC",
        phases: [
          phase(cycle_count: 3, every: 1, unit: :week, code: "weekly_intro", override: "-50%"),
          phase(cycle_count: nil, every: 1, unit: :month, code: "standard")
        ]
      }
    end
    let(:rates) { [rate("A", Time.utc(2026, 1, 1)), rate("B", Time.utc(2026, 8, 20)), rate("C", Time.utc(2026, 9, 15))] }
    # The cadence in this example comes from the phase overrides, so the rates only need to
    # answer where they take effect and what a phase would fall back to.
    let(:asked_at) { Time.utc(2026, 12, 1) }

    def rate(label, effective_from)
      Struct.new(:label, :effective_from, :billing_interval_count, :billing_interval_unit)
        .new(label, effective_from, 1, :month)
    end

    # The flat surface carries the cycle it came from, so a per-cycle assertion groups on it
    # exactly as the billing_segments index does.
    def slices_by_cycle
      schedule.segments_due_by(asked_at).group_by(&:cycle_started_at).first(4)
    end

    it "runs weekly for three cycles, then on the card's own month" do
      windows = slices_by_cycle.map do |started_at, group|
        ["#{started_at.to_date} -> #{group.last.ended_at.to_date}", group.first.rate_phase_code]
      end

      expect(windows).to eq(
        [["2026-08-12 -> 2026-08-17", "weekly_intro"],
          ["2026-08-17 -> 2026-08-24", "weekly_intro"],
          ["2026-08-24 -> 2026-08-31", "weekly_intro"],
          ["2026-08-31 -> 2026-09-30", "standard"]]
      )
    end

    # A cycle is one turn of the interval clamped by the card's life, so the anchor decides
    # where the boundary falls and the card's start decides where the first cycle opens.
    it "opens the first cycle where the card starts, not on the anchor" do
      started_at, segments = slices_by_cycle.first

      expect(started_at).to eq(Time.utc(2026, 8, 12))
      expect(segments.last.ended_at).to eq(Time.utc(2026, 8, 17))
    end

    it "prices each segment at its share of a whole interval" do
      billed = slices_by_cycle.map { |_cycle, group| group.map { [it.rate.label, it.proration_ratio] } }

      expect(billed).to eq(
        [[["A", 5.fdiv(7)]],
          [["A", 3.fdiv(7)], ["B", 4.fdiv(7)]],
          [["B", 1.0]],
          [["B", 1.fdiv(2)], ["C", 1.fdiv(2)]]]
      )
    end

    # Two different facts, and the totals tell them apart. A cycle clamped by the card's
    # start bills less than a whole interval — 5 of its 7 days. A cycle merely cut by a rate
    # change bills exactly one, however many segments it ends up with.
    it "bills a clamped cycle short and a cut cycle whole" do
      totals = slices_by_cycle.map { |_cycle, group| group.sum(&:proration_ratio) }

      expect(totals).to eq([5.fdiv(7), 1.0, 1.0, 1.0])
    end

    # The two fields the flat surface carries purely for attribution: which phase priced the
    # slice, and the override it priced it with. Neither shows up in an amount, so nothing
    # else in the suite would notice them both returning nil.
    it "carries the phase that priced each slice onto the flat surface" do
      attributed = schedule.segments_due_by(asked_at).first(6).map do |segment|
        [segment.rate.label, segment.rate_phase_code, segment.rate_override&.label]
      end

      expect(attributed).to eq(
        [["A", "weekly_intro", "-50%"],
          ["A", "weekly_intro", "-50%"],
          ["B", "weekly_intro", "-50%"],
          ["B", "weekly_intro", "-50%"],
          ["B", "standard", nil],
          ["C", "standard", nil]]
      )
    end

    it "falls due when each cycle closes in arrears" do
      expect(slices_by_cycle.map { |_cycle, group| group.last.billing_at.to_date.to_s })
        .to eq(["2026-08-17", "2026-08-24", "2026-08-31", "2026-09-30"])
    end

    # The only thing billing timing changes: same cycles, same segments, earlier due dates.
    context "when the card bills in advance" do
      let(:timing) { :advance }

      it "falls due when each cycle opens" do
        expect(slices_by_cycle.map { |_cycle, group| group.first.billing_at.to_date.to_s })
          .to eq(["2026-08-12", "2026-08-17", "2026-08-24", "2026-08-31"])
      end

      it "produces the same cycles as arrears" do
        arrears = described_class.new(**arguments.merge(terms: Billing::Terms.new(timing: :arrears, prorated: true)))
          .segments_due_by(asked_at).group_by(&:cycle_started_at).first(4)

        expect(slices_by_cycle.map { |started_at, group| [started_at, group.last.ended_at] })
          .to eq(arrears.map { |started_at, group| [started_at, group.last.ended_at] })
      end
    end
  end

  # Decision #56 says the cadence through an unpriced window comes from the EARLIEST rate — for
  # its interval only, never for its price. Every existing example of this has a single rate, so
  # the earliest and the latest are the same row and nothing pins which one is read. Found by
  # mutating the fallback from `min_by` to `max_by`: no example failed.
  describe "the cadence before any rate is in force, with more than one rate to choose from" do
    let(:anchor_date) { Date.new(2026, 1, 1) }
    let(:starts_at) { Time.utc(2026, 1, 1) }
    let(:phases) { [phase(cycle_count: nil, every: nil, unit: nil)] }
    let(:rates) { [card_rate(Time.utc(2026, 6, 1), 1, :week), card_rate(Time.utc(2026, 9, 1), 1, :month)] }

    it "bills nothing before the first rate and preserves the cycle numbering afterwards" do
      expect(schedule.segments_due_by(Time.utc(2026, 3, 1))).to be_empty
      first = schedule.segments_due_by(Time.utc(2026, 6, 11)).first

      expect(first.cycle_index).to eq(21)
      expect(first.started_at).to eq(Time.utc(2026, 6, 1))
      expect(first.ended_at).to eq(Time.utc(2026, 6, 4))
    end
  end

  # LAGO-1766, the cycles Tiago published from staging on 2026-08-10: a monthly card with
  # a six-cycle weekly intro phase. The tail re-anchors on the day the intro ended, so
  # billing moves to the 21st for good instead of returning to the 10th.
  describe "with the LAGO-1766 phase transition" do
    subject(:schedule) do
      described_class.new(
        anchor_date: Date.new(2026, 8, 10),
        starts_at: Time.utc(2026, 8, 10),
        rates:,
        terms: Billing::Terms.new(timing: :arrears, prorated: true),
        timezone: "UTC",
        phases: [
          phase(cycle_count: 6, every: 1, unit: :week, code: "weekly_intro"),
          phase(cycle_count: nil, every: 1, unit: :month, code: "standard")
        ]
      )
    end

    let(:end_on) { Time.utc(2027, 12, 30) }

    it "reproduces the published cycles" do
      expect(windows(schedule.segments_due_by(end_on))).to eq(
        [
          "2026-08-10 -> 2026-08-16", "2026-08-17 -> 2026-08-23", "2026-08-24 -> 2026-08-30",
          "2026-08-31 -> 2026-09-06", "2026-09-07 -> 2026-09-13", "2026-09-14 -> 2026-09-20",
          "2026-09-21 -> 2026-10-20", "2026-10-21 -> 2026-11-20", "2026-11-21 -> 2026-12-20",
          "2026-12-21 -> 2027-01-20", "2027-01-21 -> 2027-02-20", "2027-02-21 -> 2027-03-20",
          "2027-03-21 -> 2027-04-20", "2027-04-21 -> 2027-05-20", "2027-05-21 -> 2027-06-20",
          "2027-06-21 -> 2027-07-20", "2027-07-21 -> 2027-08-20", "2027-08-21 -> 2027-09-20",
          "2027-09-21 -> 2027-10-20", "2027-10-21 -> 2027-11-20", "2027-11-21 -> 2027-12-20"
        ]
      )
    end

    it "keeps numbering across the phase change" do
      expect(schedule.segments_due_by(end_on).map(&:cycle_index)).to eq((0..20).to_a)
    end

    it "reports which phase each cycle was billed under" do
      codes = schedule.segments_due_by(end_on).map { |cycle| cycle.rate_phase_code }

      expect(codes.first(6).uniq).to eq(["weekly_intro"])
      expect(codes.drop(6).uniq).to eq(["standard"])
    end

    # The point of the ticket, and the thing that reads as a regression until you know it is
    # ruled: the monthly tail bills on the 21st for good, not back on the card's own 10th.
    # A phase starts where the previous one ended and runs its own cadence from there
    # (Reading B, chained phases — the `billing_anchor_mode` that would have kept the 10th was
    # built and reverted on 2026-08-03).
    it "reports the published next billing date, on the day the intro ended" do
      asked_at = Time.utc(2026, 9, 25)

      expect(schedule.next_billing_at(after: asked_at)).to eq(Time.utc(2026, 10, 21))
    end

    it "never returns to the card's own anchor day once the cadence has changed" do
      billing_days = schedule.segments_due_by(end_on).drop(6).map { |segment| segment.billing_at.day }

      expect(billing_days.uniq).to eq([21])
    end
  end
end
