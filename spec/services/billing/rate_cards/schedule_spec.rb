# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::RateCards::Schedule do
  subject(:schedule) do
    described_class.new(anchor_date:, phases:, rates:, prorated:, timezone:, starts_at:, timing:, ends_at:)
  end

  let(:anchor_date) { Date.new(2022, 1, 1) }
  let(:phases) { [phase(cycle_count: nil, every: 1, unit: :month)] }
  let(:rates) { [card_rate(Time.utc(2000, 1, 1))] }
  let(:prorated) { true }
  let(:timezone) { "UTC" }
  let(:starts_at) { Time.utc(2022, 1, 15) }
  let(:timing) { :arrears }
  let(:ends_at) { nil }

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

  # No position: the phases are handed in the order they should bill, and the schedule's
  # stable sort keeps unpositioned ones where they were given.
  def phase(cycle_count:, every:, unit:, code: "standard", override: nil, position: nil)
    described_class::Phase.new(
      position:,
      cycle_count:,
      code:,
      override: interval_override(every, unit, override)
    )
  end

  # The plan shows bounds inclusive, so the exclusive end reads as the day before.
  def windows(cycles)
    cycles.map { |cycle| "#{cycle.started_at.to_date} -> #{(cycle.ended_at - 1.day).to_date}" }
  end

  it "covers exactly the billing timings the catalog allows" do
    expect(described_class::TIMINGS).to match_array(RateCard::BILLING_TIMINGS.keys)
  end

  describe "validation" do
    it "rejects an unknown timing" do
      expect { described_class.new(anchor_date:, phases:, rates:, prorated:, timezone:, starts_at:, timing: :upfront) }
        .to raise_error(ArgumentError, /Unknown billing timing/)
    end

    it "rejects an end before the start" do
      expect { described_class.new(anchor_date:, phases:, rates:, prorated:, timezone:, starts_at:, timing:, ends_at: starts_at - 1.day) }
        .to raise_error(ArgumentError, /precedes starts_at/)
    end

    it "rejects an empty phase list" do
      expect { described_class.new(anchor_date:, phases: [], rates:, prorated:, timezone:, starts_at:, timing:) }
        .to raise_error(ArgumentError, /at least one phase/)
    end

    # A bounded last phase stops producing cycles while the card is still live, which
    # downstream reads as nothing being due rather than as an error.
    it "rejects a bounded last phase" do
      broken = [phase(cycle_count: 6, every: 1, unit: :month)]

      expect { described_class.new(anchor_date:, phases: broken, rates:, prorated:, timezone:, starts_at:, timing:) }
        .to raise_error(ArgumentError, /last phase must run to the end/)
    end

    it "rejects an open phase that is not the last" do
      broken = [phase(cycle_count: nil, every: 1, unit: :week), phase(cycle_count: nil, every: 1, unit: :month)]

      expect { described_class.new(anchor_date:, phases: broken, rates:, prorated:, timezone:, starts_at:, timing:) }
        .to raise_error(ArgumentError, /only the last phase/)
    end
  end

  describe "#cycles_due_by" do
    it "clamps the first cycle to the start rather than to the boundary before it" do
      expect(windows(schedule.cycles_due_by(Time.utc(2022, 3, 1))))
        .to eq(["2022-01-15 -> 2022-01-31", "2022-02-01 -> 2022-02-28"])
    end

    # A cycle running over the timestamp but closing after it has not fallen due yet.
    it "leaves out a cycle that has not closed by the timestamp" do
      expect(windows(schedule.cycles_due_by(Time.utc(2022, 2, 10)))).to eq(["2022-01-15 -> 2022-01-31"])
    end

    # The last one closes exactly on the timestamp asked about, so it has fallen due.
    it "numbers cycles from zero, counting from the card start" do
      expect(schedule.cycles_due_by(Time.utc(2022, 5, 1)).map(&:index)).to eq([0, 1, 2, 3])
    end

    it "returns nothing when nothing has fallen due" do
      expect(schedule.cycles_due_by(starts_at)).to be_empty
    end

    context "when the card starts before the anchor" do
      let(:starts_at) { Time.utc(2021, 12, 20) }

      it "still opens at cycle 0, clamped to the start" do
        cycle = schedule.cycles_due_by(Time.utc(2022, 1, 1)).sole

        expect(cycle.index).to eq(0)
        expect(cycle.started_at...cycle.ended_at).to eq(Time.utc(2021, 12, 20)...Time.utc(2022, 1, 1))
      end
    end

    context "when the schedule ends" do
      let(:ends_at) { Time.utc(2022, 3, 20) }

      it "clamps the final cycle to the end and stops there" do
        expect(windows(schedule.cycles_due_by(Time.utc(2023, 1, 1))))
          .to eq(["2022-01-15 -> 2022-01-31", "2022-02-01 -> 2022-02-28", "2022-03-01 -> 2022-03-19"])
      end

      context "when the end falls exactly on a boundary" do
        let(:ends_at) { Time.utc(2022, 3, 1) }

        it "stops without emitting an empty cycle" do
          expect(windows(schedule.cycles_due_by(Time.utc(2023, 1, 1))))
            .to eq(["2022-01-15 -> 2022-01-31", "2022-02-01 -> 2022-02-28"])
        end
      end
    end
  end

  describe "#due_at" do
    it "bills at the end of the cycle in arrears" do
      expect(schedule.cycles_due_by(Time.utc(2022, 4, 1)).map(&:due_at))
        .to eq([Time.utc(2022, 2, 1), Time.utc(2022, 3, 1), Time.utc(2022, 4, 1)])
    end

    context "when the card bills in advance" do
      let(:timing) { :advance }

      it "bills at the start of the cycle" do
        expect(schedule.cycles_due_by(Time.utc(2022, 4, 1)).map(&:due_at))
          .to eq([Time.utc(2022, 1, 15), Time.utc(2022, 2, 1), Time.utc(2022, 3, 1), Time.utc(2022, 4, 1)])
      end
    end

    context "when a termination cuts the cycle short" do
      let(:ends_at) { Time.utc(2022, 3, 20) }

      it "bills the final cycle at the termination, not at the boundary" do
        expect(schedule.cycles_due_by(Time.utc(2023, 1, 1)).last.due_at).to eq(Time.utc(2022, 3, 20))
      end
    end
  end

  # The window is chosen deliberately, so a cycle that closed before it is left out even
  # though it has fallen due. Mapped from the old engine on 2026-08-31.
  describe "#cycles_overlapping" do
    it "keeps a cycle that reaches into the window" do
      window = Time.utc(2022, 1, 31)...Time.utc(2022, 2, 1)

      expect(windows(schedule.cycles_overlapping(window))).to eq(["2022-01-15 -> 2022-01-31"])
    end

    # The cycle closes exactly where the window opens, so it ends an instant before it. This is the case the old engine's default range fell into on every clock tick.
    it "leaves out a cycle closing exactly where the window opens" do
      window = Time.utc(2022, 2, 1)...Time.utc(2022, 2, 2)

      expect(schedule.cycles_overlapping(window)).to be_empty
    end

    it "keeps every closed cycle a wide window reaches" do
      window = Time.utc(2022, 1, 1)...Time.utc(2022, 4, 15)

      expect(windows(schedule.cycles_overlapping(window)))
        .to eq(["2022-01-15 -> 2022-01-31", "2022-02-01 -> 2022-02-28", "2022-03-01 -> 2022-03-31"])
    end

    it "leaves out a cycle that has not closed by the end of the window" do
      window = Time.utc(2022, 1, 1)...Time.utc(2022, 2, 15)

      expect(windows(schedule.cycles_overlapping(window))).to eq(["2022-01-15 -> 2022-01-31"])
    end
  end

  # What a caller needs from the ruler the cycle was measured on, so that the ruler itself
  # never leaves the layer.
  describe "Cycle" do
    subject(:cycle) { schedule.cycles_due_by(Time.utc(2022, 4, 1)).last }

    def rate(effective_from)
      Struct.new(:effective_from, :billing_interval_count, :billing_interval_unit)
        .new(effective_from, 1, :month)
    end

    it "does not expose the calendar it was measured on" do
      expect { cycle.calendar }.to raise_error(NoMethodError)
    end

    describe "#segments" do
      it "is the whole cycle when no rate changes inside it" do
        segments = cycle.segments(rates: [rate(Time.utc(2021, 1, 1))])

        expect(segments.map { |segment| [segment.started_at, segment.ended_at] })
          .to eq([[Time.utc(2022, 3, 1), Time.utc(2022, 4, 1)]])
      end

      it "splits at a rate change part-way through" do
        change = Time.utc(2022, 3, 15)
        segments = cycle.segments(rates: [rate(Time.utc(2021, 1, 1)), rate(change)])

        expect(segments.map { |segment| [segment.started_at, segment.ended_at] })
          .to eq([[Time.utc(2022, 3, 1), change], [change, Time.utc(2022, 4, 1)]])
      end
    end

    describe "#proration_ratio" do
      it "is 1.0 for a cycle measured against itself" do
        expect(cycle.proration_ratio(cycle)).to eq(1.0)
      end

      # The two sides of a rate change have to add up to one interval, whatever hour the
      # change lands at — the rule Calendar#covered_days exists to keep.
      it "shares one interval between the segments of a cut cycle" do
        segments = cycle.segments(rates: [rate(Time.utc(2021, 1, 1)), rate(Time.utc(2022, 3, 15, 14))])
        ratios = segments.map { |segment| cycle.proration_ratio(segment) }

        expect(ratios).to eq([15.fdiv(31), 16.fdiv(31)])
        expect(ratios.sum).to eq(1.0)
      end

      # A termination clamps the cycle, so it bills the share it actually ran.
      context "when the schedule ends part-way through the cycle" do
        let(:ends_at) { Time.utc(2022, 3, 20) }

        it "prorates the clamped cycle" do
          expect(cycle.proration_ratio(cycle)).to eq(19.fdiv(31))
        end
      end
    end
  end

  describe "#due_after" do
    it "reports when the first cycle beyond the timestamp falls due" do
      expect(schedule.due_after(Time.utc(2022, 3, 1))).to eq(Time.utc(2022, 4, 1))
    end

    context "when the schedule has already ended" do
      let(:ends_at) { Time.utc(2022, 3, 1) }

      it "reports nothing further" do
        expect(schedule.due_after(Time.utc(2023, 1, 1))).to be_nil
      end
    end
  end

  # What seeds the clock: unlike #due_after this counts a cycle already due but still
  # running, because nothing has billed it yet.
  describe "#next_billing_at" do
    it "waits for the first cycle to close in arrears" do
      expect(schedule.next_billing_at(starts_at)).to eq(Time.utc(2022, 2, 1))
    end

    # Every closed cycle is behind us, so the answer is the one still to close.
    it "skips the cycles that already closed" do
      expect(schedule.next_billing_at(Time.utc(2022, 3, 10))).to eq(Time.utc(2022, 4, 1))
    end

    context "when the card bills in advance" do
      let(:timing) { :advance }

      it "reports the cycle in force even though it is already due" do
        expect(schedule.next_billing_at(starts_at)).to eq(starts_at)
      end

      # The cycle covering Mar 10 opened on Mar 1 and was never billed, so the clock owes
      # that rather than the cycle ahead — which is what #due_after would answer.
      it "does not skip a due cycle that is still running" do
        expect(schedule.next_billing_at(Time.utc(2022, 3, 10))).to eq(Time.utc(2022, 3, 1))
        expect(schedule.due_after(Time.utc(2022, 3, 10))).to eq(Time.utc(2022, 4, 1))
      end
    end

    context "when the schedule has already ended" do
      let(:ends_at) { Time.utc(2022, 3, 1) }

      it "reports nothing further" do
        expect(schedule.next_billing_at(Time.utc(2023, 1, 1))).to be_nil
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
      expect(schedule.cycles_due_by(asked_at).size).to eq(120)
      expect(Billing::Calendar).to have_received(:new).once
    end

    context "when a phase changes the cadence" do
      let(:phases) do
        [phase(cycle_count: 3, every: 1, unit: :week, code: "intro"),
          phase(cycle_count: nil, every: 1, unit: :month)]
      end

      it "builds one calendar per cadence, not one per cycle" do
        expect(schedule.cycles_due_by(asked_at).size).to eq(121)
        expect(Billing::Calendar).to have_received(:new).twice
      end
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
        prorated: true,
        timezone: "UTC",
        timing:,
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

    def cycles = schedule.cycles_due_by(asked_at).first(4)

    it "runs weekly for three cycles, then on the card's own month" do
      expect(cycles.map { |cycle| ["#{cycle.started_at.to_date} -> #{cycle.ended_at.to_date}", cycle.phase.code] }).to eq(
        [["2026-08-12 -> 2026-08-17", "weekly_intro"],
          ["2026-08-17 -> 2026-08-24", "weekly_intro"],
          ["2026-08-24 -> 2026-08-31", "weekly_intro"],
          ["2026-08-31 -> 2026-09-30", "standard"]]
      )
    end

    # A cycle is one turn of the interval clamped by the card's life, so the anchor decides
    # where the boundary falls and the card's start decides where the first cycle opens.
    it "opens the first cycle where the card starts, not on the anchor" do
      expect(cycles.first.started_at).to eq(Time.utc(2026, 8, 12))
      expect(cycles.first.ended_at).to eq(Time.utc(2026, 8, 17))
    end

    it "prices each segment at its share of a whole interval" do
      billed = cycles.map do |cycle|
        cycle.segments(rates:).map { |segment| [segment.rate.label, cycle.proration_ratio(segment)] }
      end

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
      totals = cycles.map do |cycle|
        cycle.segments(rates:).sum { |segment| cycle.proration_ratio(segment) }
      end

      expect(totals).to eq([5.fdiv(7), 1.0, 1.0, 1.0])
    end

    it "falls due when each cycle closes in arrears" do
      expect(cycles.map { |cycle| cycle.due_at.to_date.to_s })
        .to eq(["2026-08-17", "2026-08-24", "2026-08-31", "2026-09-30"])
    end

    # The only thing billing timing changes: same cycles, same segments, earlier due dates.
    context "when the card bills in advance" do
      let(:timing) { :advance }

      it "falls due when each cycle opens" do
        expect(cycles.map { |cycle| cycle.due_at.to_date.to_s })
          .to eq(["2026-08-12", "2026-08-17", "2026-08-24", "2026-08-31"])
      end

      it "produces the same cycles as arrears" do
        arrears = described_class.new(**arguments.merge(timing: :arrears)).cycles_due_by(asked_at).first(4)

        expect(cycles.map { |cycle| [cycle.started_at, cycle.ended_at] }).to eq(arrears.map { |cycle| [cycle.started_at, cycle.ended_at] })
      end
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
        prorated: true,
        timezone: "UTC",
        timing: :arrears,
        phases: [
          phase(cycle_count: 6, every: 1, unit: :week, code: "weekly_intro"),
          phase(cycle_count: nil, every: 1, unit: :month, code: "standard")
        ]
      )
    end

    let(:end_on) { Time.utc(2027, 12, 30) }

    it "reproduces the published cycles" do
      expect(windows(schedule.cycles_due_by(end_on))).to eq(
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
      expect(schedule.cycles_due_by(end_on).map(&:index)).to eq((0..20).to_a)
    end

    it "reports which phase each cycle was billed under" do
      codes = schedule.cycles_due_by(end_on).map { |cycle| cycle.phase.code }

      expect(codes.first(6).uniq).to eq(["weekly_intro"])
      expect(codes.drop(6).uniq).to eq(["standard"])
    end

    it "reports the published next billing date" do
      expect(schedule.due_after(end_on)).to eq(Time.utc(2028, 1, 21))
    end
  end
end
