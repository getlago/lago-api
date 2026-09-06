# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Schedule do
  subject(:schedule) { schedule_with(anchor_policy) }

  # The anchor policy is still an axis of this spec rather than a detail of one example, but
  # only one mode ships (LAGO-1766, see Billing::AnchorPolicy), so every case is built once.
  # The helper stays because the parameter stays: the day a second mode returns, the cases
  # under "the anchor policy on a cadence change" gain a second half again.
  def schedule_with(policy)
    described_class.new(anchor_date:, timezone:, starts_at:, ends_at:, terms:, rates:, phases:, anchor_policy: policy)
  end

  let(:anchor_policy) { Billing::AnchorPolicy::Realigning }
  let(:anchor_date) { Date.new(2024, 1, 1) }
  let(:timezone) { "UTC" }
  let(:starts_at) { local("2024-01-01 00:00") }
  let(:ends_at) { nil }
  let(:terms) { Billing::Terms.new(timing: :arrears, prorated: false) }
  let(:rates) { Billing::RateTimeline.new([monthly_rate]) }
  let(:monthly_rate) { rate("2024-01-01 00:00", code: "monthly") }
  let(:phases) { [] }

  # Rates and overrides reach the engine as data: the walk only ever reads an effective
  # date and an interval off them, so a Struct proves the coupling is that thin.
  let(:rate_class) do
    Struct.new(:code, :effective_from, :billing_interval_count, :billing_interval_unit, keyword_init: true)
  end

  let(:override_class) do
    Struct.new(:code, :billing_interval_count, :billing_interval_unit, keyword_init: true)
  end

  def rate(effective_from, count: 1, unit: "month", code: "rate")
    rate_class.new(
      code:,
      effective_from: local(effective_from),
      billing_interval_count: count,
      billing_interval_unit: unit
    )
  end

  def override(count: nil, unit: nil, code: "override")
    override_class.new(code:, billing_interval_count: count, billing_interval_unit: unit)
  end

  def phase(position:, cycle_count:, override: nil, code: "phase")
    described_class::Phase.new(position:, cycle_count:, code:, override:)
  end

  # Spec dates are written the way a customer reads them: in their own timezone.
  def local(value, zone = timezone)
    Time.find_zone!(zone).parse(value)
  end

  describe "#segments_due_by" do
    context "with an arrears card on a monthly cadence" do
      it "returns the cycles that have closed" do
        due = schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(due.map(&:started_at)).to eq([local("2024-01-01 00:00"), local("2024-02-01 00:00")])
      end

      it "closes each cycle where the next one opens" do
        due = schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(due.map(&:ended_at)).to eq([local("2024-02-01 00:00"), local("2024-03-01 00:00")])
      end

      it "bills each segment at its close" do
        due = schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(due.map(&:billing_at)).to eq([local("2024-02-01 00:00"), local("2024-03-01 00:00")])
      end

      it "numbers cycles from zero" do
        due = schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(due.map(&:cycle_index)).to eq([0, 1])
      end

      it "records where each cycle opened" do
        due = schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(due.map(&:cycle_started_at)).to eq([local("2024-01-01 00:00"), local("2024-02-01 00:00")])
      end

      it "carries the rate in force" do
        due = schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(due.map(&:rate)).to eq([monthly_rate, monthly_rate])
      end

      it "returns nothing while the first cycle is still open" do
        expect(schedule.segments_due_by(local("2024-01-31 23:59:59"))).to be_empty
      end

      it "keeps a cycle due once the walk has run further" do
        schedule.segments_due_by(local("2024-06-01 00:00"))

        expect(schedule.segments_due_by(local("2024-03-01 00:00")).map(&:cycle_index)).to eq([0, 1])
      end

      it "walks further when a later query needs it" do
        schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(schedule.segments_due_by(local("2024-06-01 00:00")).map(&:cycle_index)).to eq([0, 1, 2, 3, 4])
      end
    end

    context "with an advance card on a monthly cadence" do
      let(:terms) { Billing::Terms.new(timing: :advance, prorated: false) }

      it "bills each segment at its open" do
        due = schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(due.map(&:billing_at)).to eq([
          local("2024-01-01 00:00"), local("2024-02-01 00:00"), local("2024-03-01 00:00")
        ])
      end

      it "bills the first cycle on the day the card starts" do
        expect(schedule.segments_due_by(local("2024-01-01 00:00")).map(&:cycle_index)).to eq([0])
      end
    end

    context "when the card has no rate at all" do
      let(:rates) { Billing::RateTimeline.new([]) }

      it "has nothing to walk" do
        expect(schedule.segments_due_by(local("2024-06-01 00:00"))).to be_empty
      end
    end

    context "when the card starts before its first rate takes effect" do
      let(:monthly_rate) { rate("2024-03-01 00:00", code: "monthly") }

      it "lays out the unpriced cycles without billing them" do
        due = schedule.segments_due_by(local("2024-05-01 00:00"))

        expect(due.map(&:started_at)).to eq([local("2024-03-01 00:00"), local("2024-04-01 00:00")])
      end

      it "keeps the cycle numbering of the walk, gaps included" do
        due = schedule.segments_due_by(local("2024-05-01 00:00"))

        expect(due.map(&:cycle_index)).to eq([2, 3])
      end
    end
  end

  describe "#segments_overlapping" do
    # The two queries answer different questions on the same schedule: what the clock owes
    # now, and what covers a stretch of time. An arrears cycle in progress is in the second
    # and not the first — it has not closed, so nothing is due for it yet.
    it "returns the cycle in progress, which is not yet due" do
      overlapping = schedule.segments_overlapping(local("2024-01-01 00:00")..local("2024-03-01 00:00"))

      expect(overlapping.map(&:cycle_index)).to eq([0, 1, 2])
    end

    it "leaves the cycle in progress out of what is due" do
      expect(schedule.segments_due_by(local("2024-03-01 00:00")).map(&:cycle_index)).to eq([0, 1])
    end

    it "stops short of a cycle opening on an excluded end" do
      overlapping = schedule.segments_overlapping(local("2024-01-01 00:00")...local("2024-03-01 00:00"))

      expect(overlapping.map(&:cycle_index)).to eq([0, 1])
    end

    it "returns the single cycle a range inside one cycle touches" do
      overlapping = schedule.segments_overlapping(local("2024-02-10 09:00")..local("2024-02-11 09:00"))

      expect(overlapping.map(&:cycle_index)).to eq([1])
    end

    it "excludes a cycle that closed on the instant the range opens" do
      overlapping = schedule.segments_overlapping(local("2024-02-01 00:00")..local("2024-02-15 00:00"))

      expect(overlapping.map(&:cycle_index)).to eq([1])
    end

    it "returns everything covering a range that opens before the card" do
      overlapping = schedule.segments_overlapping(local("2023-06-01 00:00")..local("2024-02-15 00:00"))

      expect(overlapping.map(&:started_at)).to eq([local("2024-01-01 00:00"), local("2024-02-01 00:00")])
    end
  end

  describe "walking" do
    before { allow(rates).to receive(:segments_within).and_call_original }

    it "cuts each cycle once however often it is queried" do
      schedule.segments_due_by(local("2024-03-01 00:00"))
      schedule.segments_due_by(local("2024-03-01 00:00"))

      expect(rates).to have_received(:segments_within).exactly(3).times
    end

    it "stops at the first cycle opening after the question" do
      schedule.segments_due_by(local("2024-01-15 00:00"))

      expect(rates).to have_received(:segments_within).once
    end

    it "resumes where it stopped instead of walking again" do
      schedule.segments_due_by(local("2024-03-01 00:00"))
      schedule.segments_due_by(local("2024-04-01 00:00"))

      expect(rates).to have_received(:segments_within).exactly(4).times
    end
  end

  describe "#next_billing_at" do
    it "returns the close of the cycle in progress" do
      expect(schedule.next_billing_at(after: local("2024-01-31 23:59:59"))).to eq(local("2024-02-01 00:00"))
    end

    it "moves on once the boundary is reached, since a due date is not owed twice" do
      expect(schedule.next_billing_at(after: local("2024-02-01 00:00"))).to eq(local("2024-03-01 00:00"))
    end

    it "returns the next boundary just after one" do
      expect(schedule.next_billing_at(after: local("2024-02-01 00:00:01"))).to eq(local("2024-03-01 00:00"))
    end

    context "with an advance card" do
      let(:terms) { Billing::Terms.new(timing: :advance, prorated: false) }

      it "returns the open of the next cycle" do
        expect(schedule.next_billing_at(after: local("2024-01-15 00:00"))).to eq(local("2024-02-01 00:00"))
      end
    end

    context "when the card ends" do
      let(:ends_at) { local("2024-03-01 00:00") }

      it "owes nothing after the last cycle" do
        expect(schedule.next_billing_at(after: local("2024-03-01 00:00"))).to be_nil
      end
    end

    context "when the cadence changes at the boundary" do
      let(:rates) { Billing::RateTimeline.new([monthly_rate, weekly_rate]) }
      let(:weekly_rate) { rate("2024-02-01 00:00", unit: "week", code: "weekly") }

      # Intentional divergence from the old engine (contract BUGS #3): it read the answer
      # off the calendar of the cycle already built and returned Mar 1, the monthly
      # boundary. The next cycle is weekly and closes on Feb 8.
      it "resolves the cadence of the next cycle, not of the one just closed" do
        expect(schedule.next_billing_at(after: local("2024-02-01 00:00"))).to eq(local("2024-02-08 00:00"))
      end
    end

    context "when a rate change cuts the cycle" do
      let(:terms) { Billing::Terms.new(timing: :advance, prorated: true) }
      let(:rates) { Billing::RateTimeline.new([monthly_rate, mid_cycle_rate]) }
      let(:mid_cycle_rate) { rate("2024-01-16 00:00", code: "second") }

      it "owes the cut, because an advance segment bills when it opens" do
        expect(schedule.next_billing_at(after: local("2024-01-01 00:00"))).to eq(local("2024-01-16 00:00"))
      end
    end
  end

  describe "cutting a cycle at a rate change" do
    let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }
    let(:rates) { Billing::RateTimeline.new([monthly_rate, mid_cycle_rate]) }
    let(:mid_cycle_rate) { rate("2024-01-16 00:00", code: "second") }

    it "splits the cycle where the rate changes" do
      due = schedule.segments_due_by(local("2024-02-01 00:00"))

      expect(due.map(&:started_at)).to eq([local("2024-01-01 00:00"), local("2024-01-16 00:00")])
    end

    it "keeps both pieces in the same cycle" do
      due = schedule.segments_due_by(local("2024-02-01 00:00"))

      expect(due.map(&:cycle_index)).to eq([0, 0])
    end

    it "points both pieces at the cycle they belong to" do
      due = schedule.segments_due_by(local("2024-02-01 00:00"))

      expect(due.map(&:cycle_started_at)).to eq([local("2024-01-01 00:00"), local("2024-01-01 00:00")])
    end

    # Rule 7: a due date belongs to a segment, not to a cycle. The piece before the change
    # closes on the change and bills there instead of waiting for the cycle to end.
    it "bills the piece before the change on its own boundary" do
      due = schedule.segments_due_by(local("2024-02-01 00:00"))

      expect(due.map(&:billing_at)).to eq([local("2024-01-16 00:00"), local("2024-02-01 00:00")])
    end

    it "prices each piece as a share of the whole cycle" do
      due = schedule.segments_due_by(local("2024-02-01 00:00"))

      expect(due.map(&:proration_ratio)).to eq([Rational(15, 31), Rational(16, 31)])
    end

    it "splits the cycle without losing or gaining a day" do
      due = schedule.segments_due_by(local("2024-02-01 00:00"))

      expect(due.sum(&:proration_ratio)).to eq(1)
    end

    context "when two rate changes fall inside one cycle" do
      let(:rates) { Billing::RateTimeline.new([monthly_rate, rate("2024-01-10 00:00", code: "b"), rate("2024-01-20 00:00", code: "c")]) }

      it "cuts the cycle twice" do
        due = schedule.segments_due_by(local("2024-02-01 00:00"))

        expect(due.map(&:started_at)).to eq([
          local("2024-01-01 00:00"), local("2024-01-10 00:00"), local("2024-01-20 00:00")
        ])
      end

      it "still covers exactly one cycle" do
        due = schedule.segments_due_by(local("2024-02-01 00:00"))

        expect(due.sum(&:proration_ratio)).to eq(1)
      end

      it "prices the three pieces by their days" do
        due = schedule.segments_due_by(local("2024-02-01 00:00"))

        expect(due.map(&:proration_ratio)).to eq([Rational(9, 31), Rational(10, 31), Rational(12, 31)])
      end
    end

    context "when the rate changes on a cycle boundary" do
      let(:mid_cycle_rate) { rate("2024-02-01 00:00", code: "second") }

      it "leaves both cycles whole" do
        due = schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(due.map(&:started_at)).to eq([local("2024-01-01 00:00"), local("2024-02-01 00:00")])
      end

      it "prices each whole cycle in full" do
        due = schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(due.map(&:proration_ratio)).to eq([1, 1])
      end

      it "bills the second cycle on the new rate" do
        due = schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(due.map(&:rate)).to eq([monthly_rate, mid_cycle_rate])
      end
    end

    context "when the card is not prorated" do
      let(:terms) { Billing::Terms.new(timing: :arrears, prorated: false) }

      it "prices every piece in full" do
        due = schedule.segments_due_by(local("2024-02-01 00:00"))

        expect(due.map(&:proration_ratio)).to eq([1, 1])
      end
    end
  end

  describe "cadence changes" do
    context "when a new rate carries a different interval" do
      let(:rates) { Billing::RateTimeline.new([monthly_rate, weekly_rate]) }
      let(:weekly_rate) { rate("2024-02-01 00:00", unit: "week", code: "weekly") }

      it "re-rules the calendar from the day the cadence changed" do
        due = schedule.segments_due_by(local("2024-02-22 00:00"))

        expect(due.map(&:started_at)).to eq([
          local("2024-01-01 00:00"), local("2024-02-01 00:00"), local("2024-02-08 00:00"), local("2024-02-15 00:00")
        ])
      end

      it "gives each cadence its own cycle index" do
        due = schedule.segments_due_by(local("2024-02-22 00:00"))

        expect(due.map(&:cycle_index)).to eq([0, 1, 2, 3])
      end
    end

    context "when a phase override carries a different interval" do
      let(:phases) { [phase(position: 1, cycle_count: 2, override: override(unit: "week"))] }

      it "bills the phase on the override's cadence, then the card's own" do
        due = schedule.segments_due_by(local("2024-02-15 00:00"))

        expect(due.map(&:started_at)).to eq([
          local("2024-01-01 00:00"), local("2024-01-08 00:00"), local("2024-01-15 00:00")
        ])
      end

      it "realigns the monthly calendar on the day the phase ended" do
        due = schedule.segments_due_by(local("2024-02-15 00:00"))

        expect(due.map(&:ended_at)).to eq([
          local("2024-01-08 00:00"), local("2024-01-15 00:00"), local("2024-02-15 00:00")
        ])
      end

      it "attaches the override to the segments it prices" do
        due = schedule.segments_due_by(local("2024-02-15 00:00"))

        expect(due.map { |segment| segment.rate_override&.code }).to eq(["override", "override", nil])
      end
    end

    context "when the override changes only the count" do
      let(:phases) { [phase(position: 1, cycle_count: 1, override: override(count: 2))] }

      it "keeps the rate's unit" do
        due = schedule.segments_due_by(local("2024-05-01 00:00"))

        expect(due.map(&:ended_at)).to eq([
          local("2024-03-01 00:00"), local("2024-04-01 00:00"), local("2024-05-01 00:00")
        ])
      end
    end

    context "when the override changes only the unit" do
      let(:monthly_rate) { rate("2024-01-01 00:00", count: 3, code: "quarterly") }
      let(:phases) { [phase(position: 1, cycle_count: 1, override: override(unit: "week"))] }

      it "keeps the rate's count" do
        due = schedule.segments_due_by(local("2024-02-01 00:00"))

        expect(due.map(&:ended_at)).to eq([local("2024-01-22 00:00")])
      end
    end
  end

  # What the policy decides is where the ruler is measured from AFTER a cadence change;
  # everything up to the first change is identical whichever mode answers. Only one mode ships
  # (LAGO-1766 ruled against a second one — see Billing::AnchorPolicy), so each case below is
  # built once, under Realigning.
  #
  # Every case used to be built twice on the same inputs and the two answers asserted next to
  # each other. The `Fixed` half of each pair was DELETED with the mode; what it asserted is
  # recorded in a comment where it stood, so a reader can see the coverage went deliberately
  # rather than got lost. The seam is untouched, so a second mode restores the pairs.
  describe "the anchor policy on a cadence change" do
    let(:realigning) { schedule_with(Billing::AnchorPolicy::Realigning) }

    def starts(schedule, by:)
      schedule.segments_due_by(local(by)).map(&:started_at)
    end

    def ends(schedule, by:)
      schedule.segments_due_by(local(by)).map(&:ended_at)
    end

    def ratios(schedule, by:)
      schedule.segments_due_by(local(by)).map(&:proration_ratio)
    end

    def segments_of_cycle(schedule, index, by:)
      schedule.segments_due_by(local(by)).select { it.cycle_index == index }
    end

    # The contract's worked example: monthly anchored Jan 1, a weekly stretch, then monthly
    # again. Realigning ends up billing on the 15th.
    context "with a cadence that changes and then changes back" do
      let(:rates) { Billing::RateTimeline.new([monthly_rate, weekly_rate, monthly_again]) }
      let(:weekly_rate) { rate("2024-02-01 00:00", unit: "week", code: "weekly") }
      let(:monthly_again) { rate("2024-02-15 00:00", code: "monthly-again") }

      it "measures each cadence from the day it took over, and lands on the 15th" do
        expect(ends(realigning, by: "2024-03-15 00:00")).to eq([
          local("2024-02-01 00:00"), local("2024-02-08 00:00"),
          local("2024-02-15 00:00"), local("2024-03-15 00:00")
        ])
      end

      # DELETED with the mode: "measures both cadences from the original anchor, and comes
      # back to the 1st" asserted that Fixed put the weekly cycles on the Jan 1 grid (Feb 5,
      # Feb 12), made Feb 15 a rate cut inside the Feb 12 cycle rather than a boundary, and
      # resumed monthly on Feb 19 closing Mar 1.
      #
      # DELETED with the mode: "leaves the cycles before the first change alone under either
      # policy" asserted the two policies agree up to the first cadence change. With one mode
      # there is nothing to compare it against; the claim it made is now a property of
      # Schedule#align_calendar_to, which consults no policy for the first cycle.
    end

    context "when a new rate changes the cadence" do
      let(:rates) { Billing::RateTimeline.new([monthly_rate, weekly_rate]) }
      let(:weekly_rate) { rate("2024-02-01 00:00", unit: "week", code: "weekly") }

      it "opens the weekly cycles on the day the rate took effect" do
        expect(starts(realigning, by: "2024-02-22 00:00")).to eq([
          local("2024-01-01 00:00"), local("2024-02-01 00:00"),
          local("2024-02-08 00:00"), local("2024-02-15 00:00")
        ])
      end

      # DELETED with the mode: "opens them on the weekly fenceposts of the original anchor"
      # asserted Fixed measured the weekly ruler from Jan 1 (Feb 5, Feb 12), the first weekly
      # cycle being what was left of the fencepost the change fell in.

      it "owes the next close a week after the change" do
        expect(realigning.next_billing_at(after: local("2024-02-01 00:00"))).to eq(local("2024-02-08 00:00"))
      end

      # DELETED with the mode: "owes it on the original anchor's next weekly fencepost
      # instead" asserted next_billing_at was 2024-02-05 under Fixed.

      context "when the card prorates" do
        let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }

        it "bills every realigned cycle in full, because each one is whole" do
          expect(ratios(realigning, by: "2024-02-22 00:00")).to eq([1, 1, 1, 1])
        end

        # DELETED with the mode: "prices the fixed transitional cycle by the days it covers"
        # asserted [1, 4/7, 1, 1] — a fixed anchor is what produced a partial cycle at all,
        # the transitional one covering four of the seven days of the fencepost the change
        # landed in. Realignment never produces one, which is the whole point of the mode
        # that shipped.
      end
    end

    context "when a phase override changes the cadence" do
      let(:phases) { [phase(position: 1, cycle_count: 2, override: override(unit: "week"))] }
      let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }

      it "runs the monthly cycle from the day the phase ended" do
        expect(ends(realigning, by: "2024-02-15 00:00")).to eq([
          local("2024-01-08 00:00"), local("2024-01-15 00:00"), local("2024-02-15 00:00")
        ])
      end

      it "prices the realigned monthly cycle in full" do
        expect(ratios(realigning, by: "2024-02-15 00:00")).to eq([1, 1, 1])
      end

      # DELETED with the mode: "runs it only to the original monthly boundary" asserted the
      # monthly cycle after the phase closed on 2024-02-01, and "prices the fixed one by the
      # days left of January" asserted [1, 1, 17/31] for it.
    end

    # DELETED with the mode: the context "when the override changes only the count" here held
    # only Fixed assertions — "gives both policies the same schedule" (a two-mode comparison
    # with nothing left to compare) and "keeps billing on the 1st" (ends Mar 1, Apr 1, May 1,
    # because a two-month phase closes on a fencepost the original monthly calendar already
    # has, so both policies coincided). The surviving half of that pair is the identically
    # configured "keeps the rate's unit" under "#segments_due_by", which pins the same three
    # ends on the default schedule.

    context "when the override changes only the unit" do
      let(:monthly_rate) { rate("2024-01-01 00:00", count: 3, code: "quarterly") }
      let(:phases) { [phase(position: 1, cycle_count: 1, override: override(unit: "week"))] }
      let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }

      it "starts the quarter on the day the three weeks ended" do
        expect(ends(realigning, by: "2024-05-01 00:00")).to eq([
          local("2024-01-22 00:00"), local("2024-04-22 00:00")
        ])
      end

      # DELETED with the mode: "finishes the quarter the original anchor had already started"
      # asserted ends 2024-01-22 then 2024-04-01 under Fixed, and "prices the fixed quarter by
      # the days left in it" asserted [1, 70/91] — 70 of the 91 days of [Jan 1, Apr 1).
    end

    context "with a month-end anchor and a cadence change across a leap February" do
      let(:anchor_date) { Date.new(2024, 1, 31) }
      let(:starts_at) { local("2024-01-31 00:00") }
      let(:phases) { [phase(position: 1, cycle_count: 1, override: override(unit: "week"))] }
      let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }

      it "re-rules the monthly calendar onto the 7th, where no February clamping applies" do
        expect(ends(realigning, by: "2024-05-01 00:00")).to eq([
          local("2024-02-07 00:00"), local("2024-03-07 00:00"), local("2024-04-07 00:00")
        ])
      end

      # DELETED with the mode: "comes back onto the clamped month-end calendar" asserted ends
      # Feb 7, Feb 29, Mar 31, Apr 30 — boundaries re-derived from the anchor rather than
      # accumulated, so a month-end calendar clamps to Feb 29 and returns to the 31st instead
      # of drifting. "prices the fixed transitional cycle against the short February window"
      # asserted [1, 22/29, 1, 1] for the same schedule. Month-end clamping itself is still
      # covered without a policy, under "#segments_due_by" and under Billing::Calendar.
    end

    context "with two cadence changes in one schedule" do
      let(:phases) do
        [
          phase(position: 1, cycle_count: 1, override: override(unit: "week"), code: "first"),
          phase(position: 2, cycle_count: 1, override: override(count: 10, unit: "day"), code: "second")
        ]
      end

      it "measures each cadence from the change before it, and drifts off the 1st" do
        expect(starts(realigning, by: "2024-04-01 00:00")).to eq([
          local("2024-01-01 00:00"), local("2024-01-08 00:00"),
          local("2024-01-18 00:00"), local("2024-02-18 00:00")
        ])
      end

      # DELETED with the mode: "measures every cadence from the original anchor, and returns
      # to the 1st" asserted starts Jan 1, Jan 8, Jan 11, Feb 1, Mar 1 — each transitional
      # cycle the remainder of the fencepost it landed in, the schedule converging back onto
      # the 1st.
    end

    context "with a rate cut inside the cycle that follows the cadence change" do
      let(:phases) { [phase(position: 1, cycle_count: 1, override: override(unit: "week"))] }
      let(:rates) { Billing::RateTimeline.new([monthly_rate, rate("2024-01-20 00:00", code: "second")]) }
      let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }

      it "cuts the realigned cycle into pieces that sum to exactly one" do
        expect(segments_of_cycle(realigning, 1, by: "2024-02-08 00:00").sum(&:proration_ratio)).to eq(1)
      end

      # DELETED with the mode: "cuts the fixed transitional cycle into pieces that sum to the
      # share it covers" asserted 24/31 rather than 1, because the fixed transitional cycle
      # was partial; "prices each fixed piece by its own days" asserted [12/31, 12/31] for the
      # two pieces. Both were about a partial cycle only a fixed anchor can produce. The
      # invariant they guarded — no day lost or invented at a cut — is what the surviving
      # example asserts on the whole cycle Realigning produces.
    end

    context "with a rate cut inside a whole cycle after the cadence change" do
      let(:phases) { [phase(position: 1, cycle_count: 1, override: override(unit: "week"))] }
      let(:rates) { Billing::RateTimeline.new([monthly_rate, rate("2024-02-10 00:00", code: "second")]) }
      let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }

      it "sums the pieces of the realigned cycle to exactly one" do
        expect(segments_of_cycle(realigning, 2, by: "2024-03-08 00:00").sum(&:proration_ratio)).to eq(1)
      end

      # DELETED with the mode: once the fixed calendar had been rejoined its cycles were whole
      # again, and "sums the pieces of the fixed cycle to exactly one" asserted that; "prices
      # them by the days of the February the fixed anchor bills" asserted [9/29, 20/29].
    end

    describe "customer timezones" do
      context "with a New York customer" do
        let(:timezone) { "America/New_York" }
        let(:rates) { Billing::RateTimeline.new([monthly_rate, weekly_rate]) }
        let(:weekly_rate) { rate("2024-02-01 00:00", unit: "week", code: "weekly") }

        it "re-anchors on the cursor's local date, five hours behind UTC" do
          expect(ends(realigning, by: "2024-02-22 00:00")).to eq([
            Time.utc(2024, 2, 1, 5), Time.utc(2024, 2, 8, 5), Time.utc(2024, 2, 15, 5), Time.utc(2024, 2, 22, 5)
          ])
        end

        # DELETED with the mode: "keeps the original anchor's local fenceposts, five hours
        # behind UTC" asserted Feb 1, Feb 5, Feb 12, Feb 19, each at 05:00 UTC.
      end

      context "with a Paris customer whose cadence changes just after the spring transition" do
        let(:timezone) { "Europe/Paris" }
        let(:anchor_date) { Date.new(2024, 3, 1) }
        let(:starts_at) { local("2024-03-01 00:00") }
        let(:monthly_rate) { rate("2024-03-01 00:00", code: "monthly") }
        let(:rates) { Billing::RateTimeline.new([monthly_rate, rate("2024-04-01 00:00", unit: "week", code: "weekly")]) }
        let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }

        it "opens the weekly cycles on the day of the change" do
          expect(ends(realigning, by: "2024-04-15 00:00")).to eq([
            local("2024-04-01 00:00"), local("2024-04-08 00:00"), local("2024-04-15 00:00")
          ])
        end

        # DELETED with the mode: "opens them on the weekly fenceposts of the March anchor"
        # asserted Apr 1, Apr 5, Apr 12, and "prices the fixed transitional cycle across the
        # transition" asserted [1, 4/7, 1] — the transitional cycle covering 4 of the 7 days
        # of [Mar 29, Apr 5), with the 23-hour Mar 31 still counting as one whole day. That
        # last point, a DST day counting as one day, is covered without a policy by
        # Billing::Calendar's own spec.
      end

      context "with a Kolkata customer" do
        let(:timezone) { "Asia/Kolkata" }
        let(:rates) { Billing::RateTimeline.new([monthly_rate, weekly_rate]) }
        let(:weekly_rate) { rate("2024-02-01 00:00", unit: "week", code: "weekly") }

        it "re-anchors on a half-hour offset" do
          expect(ends(realigning, by: "2024-02-22 00:00")).to eq([
            Time.utc(2024, 1, 31, 18, 30), Time.utc(2024, 2, 7, 18, 30),
            Time.utc(2024, 2, 14, 18, 30), Time.utc(2024, 2, 21, 18, 30)
          ])
        end

        # DELETED with the mode: "keeps the original anchor's fenceposts on that offset"
        # asserted Jan 31, Feb 4, Feb 11, Feb 18, each at 18:30 UTC.
      end

      context "with an Auckland customer whose cadence changes before the autumn transition" do
        let(:timezone) { "Pacific/Auckland" }
        let(:anchor_date) { Date.new(2024, 4, 1) }
        let(:starts_at) { local("2024-04-01 00:00") }
        let(:monthly_rate) { rate("2024-04-01 00:00", code: "monthly") }
        let(:phases) { [phase(position: 1, cycle_count: 1, override: override(count: 3, unit: "day"))] }
        let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }

        it "runs the realigned month from the day the three days ended" do
          expect(ends(realigning, by: "2024-05-10 00:00")).to eq([
            local("2024-04-04 00:00"), local("2024-05-04 00:00")
          ])
        end

        # DELETED with the mode: "runs the fixed one only to the original monthly boundary"
        # asserted Apr 4 then May 1, and "prices the fixed transitional cycle across the
        # transition" asserted [1, 27/30] — Auckland leaving DST on Apr 7 makes that day 25
        # hours long and it still counts as one, so the transitional cycle covered 27 of
        # April's 30 days.
      end
    end
  end

  describe "phases" do
    let(:weekly_override) { override(unit: "week", code: "weekly-phase") }

    context "with one bounded phase" do
      let(:phases) { [phase(position: 1, cycle_count: 2, override: weekly_override)] }

      # The default phase is appended rather than rejected: a card whose configured phases
      # are all bounded runs on its own cadence once they are over.
      it "runs on the card's own cadence once the phase is over" do
        due = schedule.segments_due_by(local("2024-02-15 00:00"))

        expect(due.map(&:cycle_index)).to eq([0, 1, 2])
      end

      it "prices the cycles after it with no override at all" do
        due = schedule.segments_due_by(local("2024-02-15 00:00"))

        expect(due.map(&:rate_override)).to eq([weekly_override, weekly_override, nil])
      end
    end

    context "with a phase whose override keeps the card's own cadence" do
      let(:phases) { [phase(position: 1, cycle_count: 1, override: override(count: 1, unit: "month"))] }

      # Realignment follows the cadence, not the phase: an override that changes only the
      # price leaves the calendar exactly where it was.
      it "keeps billing on the original anchor" do
        due = schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(due.map(&:started_at)).to eq([local("2024-01-01 00:00"), local("2024-02-01 00:00")])
      end
    end

    context "with several bounded phases" do
      let(:phases) do
        [
          phase(position: 1, cycle_count: 1, override: weekly_override, code: "first"),
          phase(position: 2, cycle_count: 1, override: override(count: 10, unit: "day"), code: "second")
        ]
      end

      it "gives each phase its own stretch of cycles" do
        due = schedule.segments_due_by(local("2024-04-01 00:00"))

        expect(due.map(&:started_at)).to eq([
          local("2024-01-01 00:00"), local("2024-01-08 00:00"), local("2024-01-18 00:00"), local("2024-02-18 00:00")
        ])
      end

      it "prices each stretch with its own override" do
        due = schedule.segments_due_by(local("2024-04-01 00:00"))

        expect(due.map { |segment| segment.rate_override&.code }).to eq(["weekly-phase", "override", nil, nil])
      end
    end

    context "with an unbounded phase alone" do
      let(:phases) { [phase(position: 1, cycle_count: nil, override: weekly_override)] }

      it "prices every cycle with it" do
        due = schedule.segments_due_by(local("2024-01-29 00:00"))

        expect(due.map { |segment| segment.rate_override&.code }).to eq(["weekly-phase"] * 4)
      end
    end

    context "with phases given out of position order" do
      let(:phases) do
        [
          phase(position: 2, cycle_count: nil, code: "last"),
          phase(position: 1, cycle_count: 2, override: weekly_override, code: "first")
        ]
      end

      it "bills them in their own order, not in the caller's" do
        due = schedule.segments_due_by(local("2024-02-15 00:00"))

        expect(due.map { |segment| segment.rate_override&.code }).to eq(["weekly-phase", "weekly-phase", nil])
      end
    end

    context "with an unbounded phase that is not last" do
      let(:phases) do
        [phase(position: 1, cycle_count: nil), phase(position: 2, cycle_count: 3)]
      end

      it "refuses to build, since nothing after it would ever bill" do
        expect { schedule }.to raise_error(ArgumentError, /unbounded phase must be the last/)
      end
    end

    context "with two unbounded phases" do
      let(:phases) do
        [phase(position: 1, cycle_count: nil), phase(position: 2, cycle_count: nil)]
      end

      it "refuses to build" do
        expect { schedule }.to raise_error(ArgumentError, /unbounded phase must be the last/)
      end
    end
  end

  describe "anchors" do
    context "when the anchor precedes the card start" do
      let(:starts_at) { local("2024-01-20 00:00") }
      let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }

      it "opens the first cycle at the card start, not at the boundary before it" do
        due = schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(due.map(&:started_at)).to eq([local("2024-01-20 00:00"), local("2024-02-01 00:00")])
      end

      it "prorates the part cycle against the whole one" do
        due = schedule.segments_due_by(local("2024-03-01 00:00"))

        expect(due.map(&:proration_ratio)).to eq([Rational(12, 31), 1])
      end
    end

    context "when the anchor is the card start" do
      it "opens the first cycle whole" do
        due = schedule.segments_due_by(local("2024-02-01 00:00"))

        expect(due.map(&:started_at)).to eq([local("2024-01-01 00:00")])
      end
    end

    context "when the anchor follows the card start" do
      let(:anchor_date) { Date.new(2024, 1, 20) }
      let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }

      # The anchor is a reference day, not a start date: the card begins in the cycle
      # before it, which the ruler counts as a negative boundary index.
      it "bills the part cycle running up to the anchor" do
        due = schedule.segments_due_by(local("2024-02-20 00:00"))

        expect(due.map(&:started_at)).to eq([local("2024-01-01 00:00"), local("2024-01-20 00:00")])
      end

      it "prorates it against the cycle that contains the card start" do
        due = schedule.segments_due_by(local("2024-02-20 00:00"))

        expect(due.map(&:proration_ratio)).to eq([Rational(19, 31), 1])
      end
    end

    context "with a month-end anchor" do
      let(:anchor_date) { Date.new(2024, 1, 31) }
      let(:starts_at) { local("2024-01-31 00:00") }

      # Boundaries are re-derived from the anchor by whole steps, so a short February
      # clamps without dragging every later boundary to the 29th.
      it "clamps through a leap February and comes back to the 31st" do
        due = schedule.segments_due_by(local("2024-05-01 00:00"))

        expect(due.map(&:started_at)).to eq([
          local("2024-01-31 00:00"), local("2024-02-29 00:00"), local("2024-03-31 00:00")
        ])
      end

      it "closes each of those cycles on the next clamped boundary" do
        due = schedule.segments_due_by(local("2024-05-01 00:00"))

        expect(due.map(&:ended_at)).to eq([
          local("2024-02-29 00:00"), local("2024-03-31 00:00"), local("2024-04-30 00:00")
        ])
      end
    end

    context "when the card starts part-way through a day" do
      let(:starts_at) { local("2024-01-15 14:30") }
      let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }

      # A card is billed by the day, so the walk opens at the start of the start day. The
      # customer does not pay for two halves of the 15th.
      it "opens the first cycle at the start of that day" do
        due = schedule.segments_due_by(local("2024-02-01 00:00"))

        expect(due.map(&:started_at)).to eq([local("2024-01-15 00:00")])
      end

      it "counts the opening day whole" do
        due = schedule.segments_due_by(local("2024-02-01 00:00"))

        expect(due.map(&:proration_ratio)).to eq([Rational(17, 31)])
      end
    end
  end

  describe "the card end" do
    let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }

    context "when it falls mid-cycle" do
      let(:ends_at) { local("2024-02-10 00:00") }

      it "closes the last cycle on it" do
        overlapping = schedule.segments_overlapping(local("2024-01-01 00:00")..local("2024-04-01 00:00"))

        expect(overlapping.map(&:ended_at)).to eq([local("2024-02-01 00:00"), local("2024-02-10 00:00")])
      end

      it "prorates the last cycle against the whole one" do
        overlapping = schedule.segments_overlapping(local("2024-01-01 00:00")..local("2024-04-01 00:00"))

        expect(overlapping.map(&:proration_ratio)).to eq([1, Rational(9, 29)])
      end

      it "bills the final piece on the end itself" do
        overlapping = schedule.segments_overlapping(local("2024-01-01 00:00")..local("2024-04-01 00:00"))

        expect(overlapping.map(&:billing_at)).to eq([local("2024-02-01 00:00"), local("2024-02-10 00:00")])
      end
    end

    context "when it falls on a boundary" do
      let(:ends_at) { local("2024-03-01 00:00") }

      it "stops after the cycle that closes there" do
        overlapping = schedule.segments_overlapping(local("2024-01-01 00:00")..local("2024-06-01 00:00"))

        expect(overlapping.map(&:ended_at)).to eq([local("2024-02-01 00:00"), local("2024-03-01 00:00")])
      end

      it "leaves both cycles whole" do
        overlapping = schedule.segments_overlapping(local("2024-01-01 00:00")..local("2024-06-01 00:00"))

        expect(overlapping.map(&:proration_ratio)).to eq([1, 1])
      end
    end

    context "when it falls before the first cycle closes" do
      let(:ends_at) { local("2024-01-10 00:00") }

      it "bills one part cycle and stops" do
        overlapping = schedule.segments_overlapping(local("2024-01-01 00:00")..local("2024-06-01 00:00"))

        expect(overlapping.map(&:proration_ratio)).to eq([Rational(9, 31)])
      end
    end

    context "when it falls on the card start" do
      let(:ends_at) { local("2024-01-01 00:00") }

      it "bills nothing" do
        expect(schedule.segments_overlapping(local("2024-01-01 00:00")..local("2024-06-01 00:00"))).to be_empty
      end
    end
  end

  describe "#consumed_ratio" do
    let(:terms) { Billing::Terms.new(timing: :advance, prorated: false) }
    let(:segment) { schedule.segments_due_by(local("2024-01-01 00:00")).sole }

    it "has consumed nothing at the start of the segment" do
      expect(schedule.consumed_ratio(segment:, at: local("2024-01-01 00:00"))).to eq(0)
    end

    it "has consumed the elapsed days mid-segment" do
      expect(schedule.consumed_ratio(segment:, at: local("2024-01-16 00:00"))).to eq(Rational(15, 31))
    end

    it "has consumed the whole cycle at its close" do
      expect(schedule.consumed_ratio(segment:, at: local("2024-02-01 00:00"))).to eq(1)
    end

    # An unprorated card still needs the elapsed share to credit an unused remainder: the
    # ratio measures time, it does not price it.
    it "measures time even when the card is not prorated" do
      expect(schedule.consumed_ratio(segment:, at: local("2024-01-16 00:00"))).to be_a(Rational)
    end

    it "refuses an instant past the close of the segment" do
      expect { schedule.consumed_ratio(segment:, at: local("2024-02-02 00:00")) }
        .to raise_error(ArgumentError, /outside the segment/)
    end

    it "refuses an instant before the segment opens" do
      expect { schedule.consumed_ratio(segment:, at: local("2023-12-31 00:00")) }
        .to raise_error(ArgumentError, /outside the segment/)
    end

    context "when the cycle was cut by a rate change" do
      let(:rates) { Billing::RateTimeline.new([monthly_rate, rate("2024-01-16 00:00", code: "second")]) }
      let(:segment) { schedule.segments_due_by(local("2024-01-16 00:00")).last }

      # The piece after the cut is priced as its own share of the cycle, so what is left of
      # it is a share of the piece: 8 of its 16 days are gone. Measured against the whole
      # 31-day cycle this read 8/31, which credits back days the piece before the cut paid
      # for — a fraction on a different basis from the fee it multiplies.
      it "measures the segment against its own length" do
        expect(schedule.consumed_ratio(segment:, at: local("2024-01-24 00:00"))).to eq(Rational(1, 2))
      end

      it "has consumed the whole segment at its close" do
        expect(schedule.consumed_ratio(segment:, at: local("2024-02-01 00:00"))).to eq(1)
      end
    end

    context "with a segment from another schedule" do
      let(:foreign) { segment.with(cycle_index: 99) }

      it "refuses to measure it" do
        expect { schedule.consumed_ratio(segment: foreign, at: local("2024-01-16 00:00")) }
          .to raise_error(ArgumentError, /not produced by this schedule/)
      end
    end
  end

  describe "customer timezones" do
    let(:terms) { Billing::Terms.new(timing: :arrears, prorated: true) }

    context "with a New York customer" do
      let(:timezone) { "America/New_York" }

      it "opens the cycle at local midnight, not UTC midnight" do
        due = schedule.segments_due_by(local("2024-02-01 00:00"))

        expect(due.map(&:started_at)).to eq([Time.utc(2024, 1, 1, 5)])
      end

      context "when the cycle contains a DST transition" do
        let(:anchor_date) { Date.new(2024, 3, 1) }
        let(:starts_at) { local("2024-03-01 00:00") }
        let(:monthly_rate) { rate("2024-03-01 00:00", code: "monthly") }
        let(:rates) { Billing::RateTimeline.new([monthly_rate, rate("2024-03-15 00:00", code: "second")]) }

        it "counts the short day as a whole day" do
          due = schedule.segments_due_by(local("2024-04-01 00:00"))

          expect(due.map(&:proration_ratio)).to eq([Rational(14, 31), Rational(17, 31)])
        end

        it "still covers exactly one cycle across the transition" do
          due = schedule.segments_due_by(local("2024-04-01 00:00"))

          expect(due.sum(&:proration_ratio)).to eq(1)
        end

        it "closes the cycle at local midnight on the far side of the transition" do
          due = schedule.segments_due_by(local("2024-04-01 00:00"))

          expect(due.last.ended_at).to eq(Time.utc(2024, 4, 1, 4))
        end
      end
    end

    context "with a Paris customer" do
      let(:timezone) { "Europe/Paris" }
      let(:anchor_date) { Date.new(2024, 6, 1) }
      let(:starts_at) { local("2024-06-01 00:00") }
      let(:monthly_rate) { rate("2024-06-01 00:00", code: "monthly") }
      let(:rates) { Billing::RateTimeline.new([monthly_rate, rate("2024-06-16 09:30", code: "second")]) }

      # The contract's worked example: the day a window opens counts whole, the day it
      # closes does not, so 16 + 14 == 30 and the cycle is neither short nor over-billed.
      it "splits a mid-day cut without inventing a day" do
        due = schedule.segments_due_by(local("2024-07-01 00:00"))

        expect(due.map(&:proration_ratio)).to eq([Rational(16, 30), Rational(14, 30)])
      end
    end

    context "with a Kolkata customer" do
      let(:timezone) { "Asia/Kolkata" }

      it "opens the cycle on a half-hour offset" do
        due = schedule.segments_due_by(local("2024-02-01 00:00"))

        expect(due.map(&:started_at)).to eq([Time.utc(2023, 12, 31, 18, 30)])
      end
    end

    context "with an Auckland customer" do
      let(:timezone) { "Pacific/Auckland" }
      let(:anchor_date) { Date.new(2024, 4, 1) }
      let(:starts_at) { local("2024-04-01 00:00") }
      let(:monthly_rate) { rate("2024-04-01 00:00", code: "monthly") }
      let(:rates) { Billing::RateTimeline.new([monthly_rate, rate("2024-04-10 00:00", code: "second")]) }

      # Auckland leaves DST on Apr 7 2024: the 7th is 25 hours long and still one day.
      it "counts the long day as a whole day" do
        due = schedule.segments_due_by(local("2024-05-01 00:00"))

        expect(due.map(&:proration_ratio)).to eq([Rational(9, 30), Rational(21, 30)])
      end

      it "keeps the cycle whole across the transition" do
        due = schedule.segments_due_by(local("2024-05-01 00:00"))

        expect(due.sum(&:proration_ratio)).to eq(1)
      end
    end
  end
end
