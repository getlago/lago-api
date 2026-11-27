# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::RateCards::Schedule do
  subject(:schedule) do
    described_class.new(anchor_date:, phases:, rates:, terms:, timezone:, starts_at:, ends_at:, termination_billing_at:)
  end

  let(:anchor_date) { Date.new(2022, 1, 1) }
  let(:traversal_start) { starts_at }
  let(:phases) { [phase(cycle_count: nil, every: 1, unit: :month)] }
  let(:rates) { [card_rate(Time.utc(2000, 1, 1))] }
  let(:prorated) { true }
  let(:timezone) { "UTC" }
  let(:starts_at) { Time.utc(2022, 1, 15) }
  let(:timing) { :arrears }
  let(:ends_at) { nil }
  let(:termination_billing_at) { nil }
  let(:terms) { Billing::Terms.new(timing:, prorated:, billing_scope:, due_on_coverage_end:) }
  let(:billing_scope) { "segment" }
  let(:due_on_coverage_end) { false }

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

  # The phases are handed in billing order. CycleWalker requires a final unbounded phase
  # and rejects an unbounded phase before it; it does not reorder phases.
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

  # Traverse cycles only in these examples; production callers select obligations by cycle.
  def due_obligations(schedule, by)
    obligations = []
    obligation = schedule.next_obligation(from: traversal_start)
    while obligation && obligation.billing_at <= by
      obligations << obligation
      obligation = schedule.next_obligation(from: obligation.segments.last.ended_at)
    end
    obligations
  end

  def due_segments(schedule, by)
    due_obligations(schedule, by).flat_map(&:segments)
  end

  describe "default billing scope" do
    subject(:schedule) { described_class.new(anchor_date:, phases:, rates:, terms:, timezone:, starts_at:) }

    let(:terms) { Billing::Terms.new(timing:, prorated:) }
    let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(Time.utc(2022, 2, 15))] }

    it "groups all priced slices of a cycle into one obligation" do
      obligation = schedule.obligation_at(Time.utc(2022, 2, 10))

      expect(obligation.billing_at).to eq(Time.utc(2022, 3, 1))
      expect(obligation.terms).to be(terms)
      expect(obligation).to be_a(Billing::Obligation)
      expect(obligation.cycle.started_at).to eq(Time.utc(2022, 2, 1))
      expect(obligation.segments.map(&:started_at)).to eq([Time.utc(2022, 2, 1), Time.utc(2022, 2, 15)])
    end
  end

  describe "#obligation_at" do
    let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(Time.utc(2022, 2, 15))] }

    it "returns nothing before the card starts" do
      expect(schedule.obligation_at(starts_at - 1.second)).to be_nil
    end

    it "selects the opening slice at a cut even when the closing slice bills there" do
      timestamp = Time.utc(2022, 2, 15)
      obligation = schedule.obligation_at(timestamp)

      expect(obligation.terms).to be(terms)
      expect(obligation.segments.sole).to have_attributes(started_at: timestamp, rate: rates.last)
      expect(obligation.billing_at).to eq(Time.utc(2022, 3, 1))
      expect(schedule.next_obligation(from: timestamp).segments.sole.started_at).to eq(timestamp)
    end

    context "with cycle scope" do
      let(:billing_scope) { ContractRateCard::BILLING_SCOPES.fetch(:cycle) }

      it "returns the whole obligation before, at and after a rate change" do
        [Time.utc(2022, 2, 14), Time.utc(2022, 2, 15), Time.utc(2022, 2, 20)].each do |timestamp|
          obligation = schedule.obligation_at(timestamp)

          expect(obligation.segments.map(&:rate)).to eq(rates)
          expect(obligation.segments.map(&:started_at)).to eq([Time.utc(2022, 2, 1), Time.utc(2022, 2, 15)])
          expect(obligation.billing_at).to eq(Time.utc(2022, 3, 1))
        end
      end
    end

    ContractRateCard::BILLING_SCOPES.each_value do |scope|
      context "with #{scope} scope and pricing starting inside the cycle" do
        let(:billing_scope) { scope }
        let(:rates) { [card_rate(Time.utc(2022, 2, 15))] }

        it "returns nothing until priced coverage begins" do
          expect(schedule.obligation_at(Time.utc(2022, 2, 14))).to be_nil
          expect(schedule.obligation_at(Time.utc(2022, 2, 15)).segments.sole.rate).to eq(rates.sole)
        end
      end
    end

    context "when pricing begins in a later cycle" do
      let(:rates) { [card_rate(Time.utc(2022, 5, 1))] }

      it "does not jump from an unpriced cycle to a later priced cycle" do
        expect(schedule.obligation_at(Time.utc(2022, 2, 10))).to be_nil
        expect(schedule.obligation_at(Time.utc(2022, 4, 30))).to be_nil
        expect(schedule.obligation_at(Time.utc(2022, 5, 1)).segments.sole.rate).to eq(rates.sole)
      end
    end

    context "when the schedule ends" do
      let(:ends_at) { Time.utc(2022, 3, 20) }

      it "excludes the end and later instants" do
        expect(schedule.obligation_at(ends_at - 1.second)).to be_a(Billing::Obligation)
        expect(schedule.obligation_at(ends_at)).to be_nil
        expect(schedule.obligation_at(ends_at + 1.day)).to be_nil
      end
    end
  end

  describe "billing scopes" do
    let(:billing_scope) { "cycle" }
    let(:rates) do
      [card_rate(Time.utc(2021, 1, 1)), card_rate(Time.utc(2022, 2, 10)), card_rate(Time.utc(2022, 2, 20))]
    end
    let(:cycle_start) { Time.utc(2022, 2, 1) }
    let(:cycle_end) { Time.utc(2022, 3, 1) }

    it "bills all slices at the cycle end and only selects the complete obligation" do
      obligation = schedule.obligation_at(Time.utc(2022, 2, 10))
      expect(obligation.billing_at).to eq(cycle_end)
      expect(obligation.segments.map(&:started_at)).to eq([cycle_start, Time.utc(2022, 2, 10), Time.utc(2022, 2, 20)])
      expect(schedule.obligation_at(cycle_start)).to eq(obligation)
      expect(schedule.obligation_at(cycle_start + 1.day)).to eq(obligation)
      expect(schedule.obligation_at(Time.utc(2022, 2, 15)).segments[1]).to eq(obligation.segments[1])
      expect(schedule.next_obligation(from: cycle_end).cycle.started_at).to eq(cycle_end)
    end

    context "when billing in advance" do
      let(:timing) { :advance }

      it "bills every slice at the first priced start" do
        obligation = schedule.obligation_at(Time.utc(2022, 2, 15))
        expect(obligation.billing_at).to eq(cycle_start)
        expect(obligation.segments.map(&:started_at)).to eq([cycle_start, Time.utc(2022, 2, 10), Time.utc(2022, 2, 20)])
        expect(schedule.next_obligation(from: cycle_end).cycle.started_at).to eq(cycle_end)
      end

      context "when the cycle begins unpriced" do
        let(:rates) { [card_rate(Time.utc(2022, 2, 10)), card_rate(Time.utc(2022, 2, 20))] }

        it "uses the first priced start and does not search future cycles for an unpriced cycle" do
          obligation = schedule.next_obligation(from: cycle_start)
          expect(obligation.billing_at).to eq(Time.utc(2022, 2, 10))
          expect(obligation.segments.map(&:started_at)).to eq([Time.utc(2022, 2, 10), Time.utc(2022, 2, 20)])
          expect(schedule.obligation_at(starts_at)).to be_nil
          expect(schedule.obligation_at(cycle_start)).to be_nil
          expect(schedule.obligation_at(Time.utc(2022, 2, 10))).to eq(obligation)
        end
      end
    end

    context "when advance fees are regrouped" do
      let(:timing) { :advance }
      let(:due_on_coverage_end) { true }

      it "bills all slices at the cycle end" do
        obligation = schedule.obligation_at(Time.utc(2022, 2, 10))
        expect(obligation.billing_at).to eq(cycle_end)
        expect(obligation.segments.map(&:started_at)).to eq([cycle_start, Time.utc(2022, 2, 10), Time.utc(2022, 2, 20)])
      end
    end

    context "with segment scope" do
      let(:billing_scope) { "segment" }

      it "returns one slice per obligation with the same parent cycle" do
        first = schedule.obligation_at(Time.utc(2022, 2, 9))
        second = schedule.next_obligation(from: first.segments.last.ended_at)
        expect(first.billing_at).to eq(Time.utc(2022, 2, 10))
        expect(first.segments.sole.started_at).to eq(cycle_start)
        expect(second.billing_at).to eq(Time.utc(2022, 2, 20))
        expect(second.cycle).to eq(first.cycle)
        expect(second.segments.sole).to be_a(Billing::Segments::Segment)
      end
    end
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

  describe "cycle information on obligations" do
    it "clamps the first cycle to the start rather than to the boundary before it" do
      expect(windows(due_segments(schedule, Time.utc(2022, 3, 1))))
        .to eq(["2022-01-15 -> 2022-01-31", "2022-02-01 -> 2022-02-28"])
    end

    # A cycle running over the timestamp but closing after it has not fallen due yet.
    it "leaves out a cycle that has not closed by the timestamp" do
      expect(windows(due_segments(schedule, Time.utc(2022, 2, 10)))).to eq(["2022-01-15 -> 2022-01-31"])
    end

    # The last one closes exactly on the timestamp asked about, so it has fallen due.
    it "numbers cycles from zero, counting from the card start" do
      expect(due_obligations(schedule, Time.utc(2022, 5, 1)).map { it.cycle.index }).to eq([0, 1, 2, 3])
    end

    it "returns nothing when nothing has fallen due" do
      expect(due_segments(schedule, starts_at)).to be_empty
    end

    context "when the card bills in advance" do
      let(:timing) { :advance }

      it "includes the first cycle as soon as it starts" do
        expect(due_obligations(schedule, starts_at).map { it.cycle.index }).to eq([0])
      end

      it "includes the cycle opening exactly at the requested time" do
        expect(due_obligations(schedule, Time.utc(2022, 2, 1)).map { it.cycle.index }).to eq([0, 1])
      end
    end

    context "when the card starts before the anchor" do
      let(:starts_at) { Time.utc(2021, 12, 20) }

      it "still opens at cycle 0, clamped to the start" do
        cycle = due_obligations(schedule, Time.utc(2022, 1, 1)).sole.cycle

        expect(cycle.index).to eq(0)
        expect(cycle.started_at...cycle.ended_at).to eq(Time.utc(2021, 12, 20)...Time.utc(2022, 1, 1))
      end
    end

    context "when the schedule ends" do
      let(:ends_at) { Time.utc(2022, 3, 20) }

      it "clamps the final cycle to the end and stops there" do
        expect(windows(due_segments(schedule, Time.utc(2023, 1, 1))))
          .to eq(["2022-01-15 -> 2022-01-31", "2022-02-01 -> 2022-02-28", "2022-03-01 -> 2022-03-19"])
      end

      context "when the end falls exactly on a boundary" do
        let(:ends_at) { Time.utc(2022, 3, 1) }

        it "stops without emitting an empty cycle" do
          expect(windows(due_segments(schedule, Time.utc(2023, 1, 1))))
            .to eq(["2022-01-15 -> 2022-01-31", "2022-02-01 -> 2022-02-28"])
        end
      end
    end
  end

  describe "when a window falls due" do
    it "bills at the end of the cycle in arrears" do
      expect(due_obligations(schedule, Time.utc(2022, 4, 1)).map(&:billing_at))
        .to eq([Time.utc(2022, 2, 1), Time.utc(2022, 3, 1), Time.utc(2022, 4, 1)])
    end

    context "when the card bills in advance" do
      let(:timing) { :advance }

      it "bills at the start of the cycle" do
        expect(due_obligations(schedule, Time.utc(2022, 4, 1)).map(&:billing_at))
          .to eq([Time.utc(2022, 1, 15), Time.utc(2022, 2, 1), Time.utc(2022, 3, 1), Time.utc(2022, 4, 1)])
      end
    end

    context "when a termination cuts the cycle short" do
      let(:ends_at) { Time.utc(2022, 3, 20) }

      it "bills the final cycle at the termination, not at the boundary" do
        expect(due_obligations(schedule, Time.utc(2023, 1, 1)).last.billing_at).to eq(Time.utc(2022, 3, 20))
      end
    end
  end

  # Each obligation carries the cycle facts needed to price its slices.
  describe "segments and their obligations" do
    let(:cut) { Time.utc(2022, 2, 15) }
    let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(cut)] }

    describe "segments due in a cycle" do
      # The bug this fixes, and the reason the release gate cannot live on the cycle: the
      # February cycle is cut on the 15th, so its first slice falls due THAT DAY. Gating on
      # the cycle's own due instant (Mar 1) withheld it, and for an arrears card whose clock
      # had already moved past the 15th, withheld it for good. QA plan R3b, decision #60 —
      # one document per transition.
      it "releases the slice before a cut as soon as the cut passes, not when the cycle closes" do
        due = due_obligations(schedule, Time.utc(2022, 2, 20))

        expect(due.map { |obligation| [obligation.segments.sole.started_at.to_date.to_s, obligation.billing_at.to_date.to_s] }).to eq(
          [["2022-01-15", "2022-02-01"],
            ["2022-02-01", "2022-02-15"]]
        )
      end

      it "still withholds the slice after the cut until its own boundary" do
        expect(due_segments(schedule, Time.utc(2022, 2, 20)).map(&:ended_at))
          .not_to include(Time.utc(2022, 3, 1))
      end

      it "retains the cycle's facts on each obligation" do
        first, second = due_obligations(schedule, Time.utc(2022, 2, 20)).last(2)

        expect([first.cycle.index, second.cycle.index]).to eq([0, 1])
        expect(second.cycle.started_at).to eq(Time.utc(2022, 2, 1))
      end

      # The two slices of one cut cycle are shares of that cycle, so they add back up to it.
      it "measures each slice against its own cycle" do
        ratios = due_obligations(schedule, Time.utc(2022, 4, 1))
          .select { it.cycle.index == 1 }
          .flat_map { |obligation| obligation.segments.map { obligation.cycle.calendar.proration_ratio(it.started_at, it.ended_at) } }

        expect(ratios).to eq([14.fdiv(28), 14.fdiv(28)])
        expect(ratios.sum).to eq(1.0)
      end

      context "when the card bills in advance" do
        let(:timing) { :advance }

        it "releases each segment when it starts, including at a rate change" do
          obligations = due_obligations(schedule, cut)

          expect(obligations.map { |obligation| [obligation.segments.sole.started_at, obligation.billing_at] }).to eq([
            [Time.utc(2022, 1, 15), Time.utc(2022, 1, 15)],
            [Time.utc(2022, 2, 1), Time.utc(2022, 2, 1)],
            [cut, cut]
          ])
        end
      end

      context "when the first rate starts inside a cycle" do
        let(:rates) { [card_rate(cut)] }

        it "does not return the unpriced segments before the first rate" do
          expect(due_segments(schedule, cut)).to be_empty
        end

        it "returns only the priced part when it falls due" do
          obligation = due_obligations(schedule, Time.utc(2022, 3, 1)).sole
          segment = obligation.segments.sole

          expect([obligation.cycle.index, segment.started_at, segment.ended_at, obligation.billing_at, segment.rate])
            .to eq([1, cut, Time.utc(2022, 3, 1), Time.utc(2022, 3, 1), rates.sole])
          expect(obligation.cycle.calendar.proration_ratio(segment.started_at, segment.ended_at)).to eq(0.5)
        end
      end

      context "when proration is disabled" do
        let(:prorated) { false }

        it "retains the same split coverage for the pricing adapter" do
          obligations = due_obligations(schedule, Time.utc(2022, 3, 1))
          first = obligations.find { it.cycle.index == 0 }
          split = obligations.select { it.cycle.index == 1 }.flat_map(&:segments)

          expect([first.segments.sole.started_at, first.segments.sole.ended_at]).to eq([starts_at, Time.utc(2022, 2, 1)])
          expect(split.map { [it.started_at, it.ended_at] }).to eq([
            [Time.utc(2022, 2, 1), cut], [cut, Time.utc(2022, 3, 1)]
          ])
        end
      end

      context "when a slice opens and closes within one day" do
        let(:rates) do
          [card_rate(Time.utc(2021, 1, 1)),
            card_rate(Time.utc(2022, 2, 15, 9)),
            card_rate(Time.utc(2022, 2, 15, 18))]
        end

        it "measures the slice as no share of the cycle on its calendar" do
          obligation = schedule.obligation_at(Time.utc(2022, 2, 15, 9))
          segment = obligation.segments.sole

          expect(obligation.cycle.calendar.proration_ratio(segment.started_at, segment.ended_at)).to eq(0.0)
        end
      end
    end
  end

  # The parent cycle carries the calendar used to measure each raw segment.
  describe "cutting a cycle and sharing it" do
    subject(:slices) do
      due_obligations(schedule, Time.utc(2022, 4, 1))
        .select { it.cycle.started_at == Time.utc(2022, 3, 1) }.flat_map(&:segments)
    end

    def bounds = slices.map { |segment| [segment.started_at, segment.ended_at] }

    def ratios
      cycle = schedule.obligation_at(Time.utc(2022, 3, 1)).cycle
      slices.map { cycle.calendar.proration_ratio(it.started_at, it.ended_at) }
    end

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

      it "measures one interval across the slices of a cut cycle" do
        expect(ratios).to eq([15.fdiv(31), 16.fdiv(31)])
        expect(ratios.sum).to eq(1.0)
      end
    end

    # A termination clamps the cycle to the share it actually ran.
    context "when the schedule ends part-way through the cycle" do
      let(:ends_at) { Time.utc(2022, 3, 20) }

      it "measures the clamped slice with the cycle calendar" do
        expect(ratios).to eq([19.fdiv(31)])
      end
    end

    # The calendar measures the same coverage even when the card does not prorate.
    context "when the card does not prorate" do
      let(:prorated) { false }
      let(:ends_at) { Time.utc(2022, 3, 20) }

      it "measures the clamped slice with the cycle calendar" do
        expect(ratios).to eq([19.fdiv(31)])
      end

      context "when a rate change cuts the cycle as well" do
        let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(Time.utc(2022, 3, 10))] }

        it "measures both clamped slices with the cycle calendar" do
          expect(ratios).to eq([9.fdiv(31), 10.fdiv(31)])
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

  describe "#next_obligation" do
    it "answers the slice starting at the requested boundary" do
      expect(schedule.next_obligation(from: starts_at)&.billing_at).to eq(Time.utc(2022, 2, 1))
    end

    it "skips a slice that started before the requested boundary" do
      expect(schedule.next_obligation(from: Time.utc(2022, 3, 10))&.billing_at).to eq(Time.utc(2022, 5, 1))
    end

    it "includes coverage starting exactly at the requested instant" do
      expect(schedule.next_obligation(from: Time.utc(2022, 3, 1))&.billing_at).to eq(Time.utc(2022, 4, 1))
    end

    context "when asked before the card starts" do
      it "returns the end of the first priced segment in arrears" do
        expect(schedule.next_obligation(from: Time.utc(2022, 1, 1))&.billing_at).to eq(Time.utc(2022, 2, 1))
      end

      context "when billing in advance" do
        let(:timing) { :advance }

        it "returns the card's start" do
          expect(schedule.next_obligation(from: Time.utc(2022, 1, 1))&.billing_at).to eq(starts_at)
        end
      end
    end

    # A cut cycle owes the piece before the cut ON the cut. Answering with the cycle's own
    # due instant dragged that piece to the end of the cycle, and for a clock already past
    # it, lost it — a 15-day arrears segment, never billed.
    context "when a rate change cuts the cycle" do
      let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(Time.utc(2022, 2, 15))] }

      it "owes the cut, not the end of the cycle" do
        expect(schedule.next_obligation(from: Time.utc(2022, 2, 1))&.billing_at).to eq(Time.utc(2022, 2, 15))
      end

      context "when billing in advance" do
        let(:timing) { :advance }

        it "finds the next segment in a cycle that is already due" do
          expect(schedule.next_obligation(from: Time.utc(2022, 2, 10))&.billing_at).to eq(Time.utc(2022, 2, 15))
        end

        it "includes the segment starting exactly at the requested instant" do
          expect(schedule.next_obligation(from: Time.utc(2022, 2, 15))&.billing_at).to eq(Time.utc(2022, 2, 15))
        end
      end
    end

    context "when pricing starts after several unpriced cycles" do
      let(:rates) { [card_rate(Time.utc(2022, 5, 1))] }

      it "finds the end of the first priced segment in arrears" do
        expect(schedule.next_obligation(from: starts_at)&.billing_at).to eq(Time.utc(2022, 6, 1))
      end

      context "when pricing starts after many unpriced daily cycles" do
        let(:anchor_date) { Date.new(2022, 1, 15) }
        let(:starts_at) { Time.utc(2022, 1, 15) }
        let(:phases) { [phase(cycle_count: nil, every: 1, unit: :day)] }
        let(:rates) { [card_rate(Time.utc(2022, 6, 1), 1, :day)] }
        let(:walker) { schedule.instance_variable_get(:@walker) }

        before { allow(walker).to receive(:cycle_after).and_call_original }

        it "walks unpriced cycles once and returns the first priced billing date" do
          expect(schedule.next_obligation(from: starts_at)&.billing_at).to eq(Time.utc(2022, 6, 2))
          expect(walker).to have_received(:cycle_after).at_most(137).times
        end
      end

      context "when billing in advance" do
        let(:timing) { :advance }

        it "finds the start of the first priced segment" do
          expect(schedule.next_obligation(from: starts_at)&.billing_at).to eq(Time.utc(2022, 5, 1))
        end
      end

      context "when the card ends before pricing starts" do
        let(:ends_at) { Time.utc(2022, 4, 1) }

        it "reports nothing further" do
          expect(schedule.next_obligation(from: starts_at)&.billing_at).to be_nil
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
        expect(schedule.next_obligation(from: Time.utc(2022, 1, 1))&.billing_at).to eq(Time.utc(2024, 1, 1))
      end
    end

    context "when the schedule has already ended" do
      let(:ends_at) { Time.utc(2022, 3, 1) }

      it "reports nothing further" do
        expect(schedule.next_obligation(from: Time.utc(2023, 1, 1))&.billing_at).to be_nil
      end
    end
  end

  describe "#obligations_due_by" do
    let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(Time.utc(2022, 2, 15))] }
    let(:cycle_start) { Time.utc(2022, 2, 1) }
    let(:cut) { Time.utc(2022, 2, 15) }
    let(:cycle_end) { Time.utc(2022, 3, 1) }

    context "with a later termination billing instant" do
      let(:ends_at) { Time.utc(2022, 2, 20) }
      let(:termination_billing_at) { Time.utc(2022, 2, 25) }

      it "marks only the final natural obligation" do
        due = schedule.obligations_due_by(termination_billing_at, from: cycle_start).to_a
        final, projected_at = due.last

        expect(due.first).to match([have_attributes(billing_at: cut, termination_billing_at: nil), cut])
        expect(final).to have_attributes(billing_at: ends_at, termination_billing_at:, terms:)
        expect(projected_at).to eq(termination_billing_at)
        expect(final.segments.sole).to have_attributes(started_at: cut, ended_at: ends_at, rate: rates.last)
      end

      it "defers the final obligation in a continuation, but not when it is selected first" do
        expect(schedule.obligations_due_by(ends_at, from: cycle_start).map { |_, at| at }).to eq([cut])
        expect(schedule.obligations_due_by(ends_at, from: cut + 1.day).map { |_, at| at }).to eq([ends_at])
        expect(schedule.obligations_due_by(termination_billing_at, from: cut, after: cut).map { |_, at| at }).to eq([termination_billing_at])
        expect(schedule.obligations_due_by(termination_billing_at, from: ends_at, after: ends_at).to_a).to be_empty
      end

      it "selects the final obligation naturally first and by its termination instant after a prior date" do
        first = schedule.obligation_at(cut + 1.day)
        continued = schedule.next_obligation(from: cut)

        expect(first.billing_at).to eq(ends_at)
        expect(continued.billing_at).to eq(ends_at)
        expect(continued.operation_billing_at(after: cut)).to eq(termination_billing_at)
        expect(schedule.next_obligation(from: ends_at)).to be_nil
        expect(continued.termination_billing_at).to eq(termination_billing_at)
      end
    end

    it "returns ordered obligations through the inclusive cutoff" do
      due = schedule.obligations_due_by(cycle_end, from: starts_at)

      expect(due.map { |obligation, at| [obligation.segments.sole.rate, at] }).to eq([
        [rates.first, cycle_start], [rates.first, cut], [rates.last, cycle_end]
      ])
    end

    it "continues at the stored coverage end even when the previous billing date was earlier" do
      due = schedule.obligations_due_by(cycle_end, from: cut, after: cycle_start)

      obligation, at = due.to_a.sole
      expect(at).to eq(cycle_end)
      expect(obligation.cycle.started_at).to eq(cycle_start)
    end

    it "skips a segment straddling the coverage end when continuing" do
      expect(schedule.obligations_due_by(cycle_end, from: cut + 1.day, after: cut).to_a).to be_empty
    end

    it "starts with the covered segment rather than a completed earlier segment" do
      due = schedule.obligations_due_by(cycle_end, from: cut + 1.day)

      obligation, at = due.to_a.sole
      expect(at).to eq(cycle_end)
      expect(obligation.segments.sole.started_at).to eq(cut)
    end

    it "includes a segment billed exactly at the coverage selection instant" do
      expect(schedule.obligations_due_by(cut, from: cut).map { |_, at| at }).to eq([cut])
    end

    context "with cycle scope" do
      let(:billing_scope) { "cycle" }

      it "returns both rate segments together at the cycle billing date" do
        expect(schedule.obligations_due_by(cut, from: cycle_start).to_a).to be_empty
        obligation, at = schedule.obligations_due_by(cycle_end, from: cycle_start).to_a.sole
        expect(at).to eq(cycle_end)
        expect(obligation.segments.map(&:rate)).to eq(rates)
      end
    end

    context "with daily cycles across a daylight saving transition" do
      let(:timezone) { "America/New_York" }
      let(:anchor_date) { Date.new(2022, 3, 12) }
      let(:starts_at) { Time.utc(2022, 3, 12, 5) }
      let(:phases) { [phase(cycle_count: nil, every: 1, unit: :day)] }
      let(:rates) { [card_rate(Time.utc(2021, 1, 1), 1, :day)] }

      it "uses customer-local boundaries on both sides of the clock change" do
        due = schedule.obligations_due_by(Time.utc(2022, 3, 15, 4), from: starts_at)

        expect(due.map { |_, at| at }).to eq([
          Time.utc(2022, 3, 13, 5), Time.utc(2022, 3, 14, 4), Time.utc(2022, 3, 15, 4)
        ])
      end
    end

    context "when the schedule has ended before pricing starts" do
      let(:ends_at) { Time.utc(2022, 3, 1) }
      let(:rates) { [card_rate(Time.utc(2022, 5, 1))] }

      it "returns no obligations, including when starting after the end" do
        expect(schedule.obligations_due_by(Time.utc(2023, 1, 1), from: starts_at).to_a).to be_empty
        expect(schedule.obligations_due_by(Time.utc(2023, 1, 1), from: ends_at).to_a).to be_empty
      end
    end
  end

  describe "cycle selection" do
    it "returns the cycle containing the timestamp" do
      cycle = schedule.obligation_at(Time.utc(2022, 2, 10)).cycle

      expect([cycle.started_at, cycle.ended_at]).to eq([Time.utc(2022, 2, 1), Time.utc(2022, 3, 1)])
    end

    context "when the card ends mid-cycle" do
      let(:ends_at) { Time.utc(2022, 3, 20) }

      it "clamps the last cycle to the termination" do
        cycle = schedule.obligation_at(ends_at - 1.second).cycle

        expect([cycle.started_at, cycle.ended_at]).to eq([Time.utc(2022, 3, 1), ends_at])
      end

      it "returns no cycle at or after the termination" do
        expect(schedule.obligation_at(ends_at)).to be_nil
        expect(schedule.obligation_at(ends_at + 1.day)).to be_nil
      end
    end

    context "when the card ends on a cycle boundary" do
      let(:ends_at) { Time.utc(2022, 3, 1) }

      it "returns no cycle starting at the termination" do
        expect(schedule.obligation_at(ends_at)).to be_nil
      end
    end
  end

  describe "priced slices within a cycle" do
    let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(Time.utc(2022, 2, 15))] }
    let(:ends_at) { Time.utc(2022, 3, 20) }

    it "selects the new slice at a rate change and none at the exclusive end" do
      expect(schedule.obligation_at(Time.utc(2022, 2, 14)).segments.sole.rate).to eq(rates.first)
      expect(schedule.obligation_at(Time.utc(2022, 2, 15)).segments.sole.rate).to eq(rates.last)
      expect(schedule.obligation_at(ends_at)).to be_nil
    end
  end

  describe "obligations due when coverage ends" do
    subject(:schedule) do
      described_class.new(anchor_date:, phases:, rates:, terms:, timezone:, starts_at:)
    end

    let(:timing) { :advance }
    let(:due_on_coverage_end) { true }
    let(:rates) { [card_rate(Time.utc(2021, 1, 1)), card_rate(Time.utc(2022, 2, 15))] }

    it "stores the end of each slice as its periodic billing instant" do
      expect(schedule.obligation_at(Time.utc(2022, 2, 1)).billing_at).to eq(Time.utc(2022, 2, 15))
    end

    it "selects the slice opening at a cut" do
      expect(schedule.obligation_at(Time.utc(2022, 2, 15)).segments.sole.started_at).to eq(Time.utc(2022, 2, 15))
    end

    it "selects by the previous coverage end" do
      expect(schedule.next_obligation(from: Time.utc(2022, 2, 1)).segments.sole.started_at).to eq(Time.utc(2022, 2, 1))
      expect(schedule.next_obligation(from: Time.utc(2022, 2, 15)).segments.sole.started_at)
        .to eq(Time.utc(2022, 2, 15))
    end

    context "when slices fall due as the terms say" do
      let(:due_on_coverage_end) { false }

      it "selects the slice opening at the cut" do
        expect(schedule.obligation_at(Time.utc(2022, 2, 15)).segments.sole.started_at).to eq(Time.utc(2022, 2, 15))
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
      expect(due_segments(schedule, asked_at).size).to eq(120)
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
        terms: Billing::Terms.new(timing:, prorated: true, billing_scope: "segment"),
        timezone: "UTC",
        phases: [
          phase(cycle_count: 3, every: 1, unit: :week, code: "weekly_intro", override: "-50%"),
          phase(cycle_count: nil, every: 1, unit: :month, code: "standard")
        ]
      }
    end
    let(:rates) { [rate("A", Time.utc(2026, 1, 1)), rate("B", Time.utc(2026, 8, 20)), rate("C", Time.utc(2026, 9, 15))] }
    let(:traversal_start) { Time.utc(2026, 8, 12) }
    # The cadence in this example comes from the phase overrides, so the rates only need to
    # answer where they take effect and what a phase would fall back to.
    let(:asked_at) { Time.utc(2026, 12, 1) }

    def rate(label, effective_from)
      Struct.new(:label, :effective_from, :billing_interval_count, :billing_interval_unit)
        .new(label, effective_from, 1, :month)
    end

    # Group priced slices by the cycle their operation owns.
    def slices_by_cycle
      due_obligations(schedule, asked_at).group_by { it.cycle.started_at }.first(4)
    end

    it "runs weekly for three cycles, then on the card's own month" do
      windows = slices_by_cycle.map do |_started_at, group|
        cycle = group.first.cycle
        ["#{cycle.started_at.to_date} -> #{group.last.segments.last.ended_at.to_date}", cycle.phase.code]
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
      _started_at, obligations = slices_by_cycle.first
      cycle = obligations.first.cycle

      expect(cycle.started_at).to eq(Time.utc(2026, 8, 12))
      expect(obligations.last.segments.last.ended_at).to eq(Time.utc(2026, 8, 17))
    end

    it "measures each slice against its cycle calendar" do
      billed = slices_by_cycle.map do |_started_at, group|
        cycle = group.first.cycle
        group.flat_map { |obligation| obligation.segments.map { [it.rate.label, cycle.calendar.proration_ratio(it.started_at, it.ended_at)] } }
      end

      expect(billed).to eq(
        [[["A", 5.fdiv(7)]],
          [["A", 3.fdiv(7)], ["B", 4.fdiv(7)]],
          [["B", 1.0]],
          [["B", 1.fdiv(2)], ["C", 1.fdiv(2)]]]
      )
    end

    # The calendar measures a clamped cycle as 5 of its 7 days, while a cycle merely cut
    # by a rate change still measures a whole interval.
    it "measures a clamped cycle short and a cut cycle whole" do
      totals = slices_by_cycle.map do |_started_at, group|
        cycle = group.first.cycle
        group.flat_map(&:segments).sum { cycle.calendar.proration_ratio(it.started_at, it.ended_at) }
      end

      expect(totals).to eq([5.fdiv(7), 1.0, 1.0, 1.0])
    end

    # The obligation's cycle retains both the phase and the override used for its slices.
    it "retains the phase that prices each slice on its parent cycle" do
      attributed = due_obligations(schedule, asked_at).flat_map do |obligation|
        obligation.segments.map { [it.rate.label, obligation.cycle.phase.code, obligation.cycle.phase.rate_override&.label] }
      end.first(6)

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
        arrears = described_class.new(**arguments.merge(terms: Billing::Terms.new(timing: :arrears, prorated: true, billing_scope: "segment")))
          .then { due_obligations(it, asked_at) }.group_by { it.cycle.started_at }.first(4)

        expect(slices_by_cycle.map { |started_at, group| [started_at, group.last.segments.last.ended_at] })
          .to eq(arrears.map { |started_at, group| [started_at, group.last.segments.last.ended_at] })
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
      expect(due_segments(schedule, Time.utc(2026, 3, 1))).to be_empty
      first = due_obligations(schedule, Time.utc(2026, 6, 11)).first

      expect(first.cycle.index).to eq(21)
      expect(first.segments.first.started_at).to eq(Time.utc(2026, 6, 1))
      expect(first.segments.first.ended_at).to eq(Time.utc(2026, 6, 4))
    end
  end

  # A monthly card with
  # a six-cycle weekly intro phase. The tail re-anchors on the day the intro ended, so
  # billing moves to the 21st for good instead of returning to the 10th.
  describe "with a weekly intro and monthly phase transition" do
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

    let(:traversal_start) { Time.utc(2026, 8, 10) }
    let(:end_on) { Time.utc(2027, 12, 30) }

    it "reproduces the published cycles" do
      expect(windows(due_segments(schedule, end_on))).to eq(
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
      expect(due_obligations(schedule, end_on).map { it.cycle.index }).to eq((0..20).to_a)
    end

    it "reports which phase each cycle was billed under" do
      codes = due_obligations(schedule, end_on).map { it.cycle.phase.code }

      expect(codes.first(6).uniq).to eq(["weekly_intro"])
      expect(codes.drop(6).uniq).to eq(["standard"])
    end

    # The important distinction is
    # ruled: the monthly tail bills on the 21st for good, not back on the card's own 10th.
    # A phase starts where the previous one ended and runs its own cadence from there
    # (Reading B, chained phases — the `billing_anchor_mode` that would have kept the 10th was
    # built and reverted on 2026-08-03).
    it "reports the published next billing date, on the day the intro ended" do
      asked_at = Time.utc(2026, 9, 25)

      expect(schedule.obligation_at(asked_at)&.billing_at).to eq(Time.utc(2026, 10, 21))
    end

    it "never returns to the card's own anchor day once the cadence has changed" do
      billing_days = due_obligations(schedule, end_on).drop(6).map { it.billing_at.day }

      expect(billing_days.uniq).to eq([21])
    end
  end
end
