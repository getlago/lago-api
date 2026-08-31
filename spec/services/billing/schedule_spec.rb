# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Schedule do
  subject(:schedule) do
    described_class.new(anchor_date:, phases:, timezone:, starts_at:, timing:, ends_at:)
  end

  let(:anchor_date) { Date.new(2022, 1, 1) }
  let(:phases) { [phase(cycle_count: nil, every: 1, unit: :month)] }
  let(:timezone) { "UTC" }
  let(:starts_at) { Time.utc(2022, 1, 15) }
  let(:timing) { :arrears }
  let(:ends_at) { nil }

  def phase(cycle_count:, every:, unit:, code: "standard", override: nil)
    described_class::Phase.new(
      cycle_count:,
      interval: Billing::Interval.new(count: every, unit:),
      code:,
      override:
    )
  end

  # The plan shows bounds inclusive, so the exclusive end reads as the day before.
  def windows(cycles)
    cycles.map { |cycle| "#{cycle.from.to_date} -> #{(cycle.to - 1.day).to_date}" }
  end

  it "covers exactly the billing timings the catalog allows" do
    expect(described_class::TIMINGS).to match_array(RateCard::BILLING_TIMINGS.keys)
  end

  describe "validation" do
    it "rejects an unknown timing" do
      expect { described_class.new(anchor_date:, phases:, timezone:, starts_at:, timing: :upfront) }
        .to raise_error(ArgumentError, /Unknown billing timing/)
    end

    it "rejects an end before the start" do
      expect { described_class.new(anchor_date:, phases:, timezone:, starts_at:, timing:, ends_at: starts_at - 1.day) }
        .to raise_error(ArgumentError, /precedes starts_at/)
    end

    it "rejects an empty phase list" do
      expect { described_class.new(anchor_date:, phases: [], timezone:, starts_at:, timing:) }
        .to raise_error(ArgumentError, /at least one phase/)
    end

    # A bounded last phase stops producing cycles while the card is still live, which
    # downstream reads as nothing being due rather than as an error.
    it "rejects a bounded last phase" do
      broken = [phase(cycle_count: 6, every: 1, unit: :month)]

      expect { described_class.new(anchor_date:, phases: broken, timezone:, starts_at:, timing:) }
        .to raise_error(ArgumentError, /last phase must run to the end/)
    end

    it "rejects an open phase that is not the last" do
      broken = [phase(cycle_count: nil, every: 1, unit: :week), phase(cycle_count: nil, every: 1, unit: :month)]

      expect { described_class.new(anchor_date:, phases: broken, timezone:, starts_at:, timing:) }
        .to raise_error(ArgumentError, /only the last phase/)
    end
  end

  describe "#cycles_due_by" do
    it "clamps the first cycle to the start rather than to the boundary before it" do
      expect(windows(schedule.cycles_due_by(Time.utc(2022, 3, 1))))
        .to eq(["2022-01-15 -> 2022-01-31", "2022-02-01 -> 2022-02-28"])
    end

    # A cycle running over the instant but closing after it has not fallen due yet.
    it "leaves out a cycle that has not closed by the instant" do
      expect(windows(schedule.cycles_due_by(Time.utc(2022, 2, 10)))).to eq(["2022-01-15 -> 2022-01-31"])
    end

    # The last one closes exactly on the instant asked about, so it has fallen due.
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
        expect(cycle.from...cycle.to).to eq(Time.utc(2021, 12, 20)...Time.utc(2022, 1, 1))
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
    it "keeps a cycle whose period reaches into the window" do
      window = Time.utc(2022, 1, 31)...Time.utc(2022, 2, 1)

      expect(windows(schedule.cycles_overlapping(window))).to eq(["2022-01-15 -> 2022-01-31"])
    end

    # The cycle closes exactly where the window opens, so its period ends an instant before
    # it. This is the case the old engine's default range fell into on every clock tick.
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

  describe "#next_due_at" do
    it "reports when the first cycle beyond the instant falls due" do
      expect(schedule.next_due_at(Time.utc(2022, 3, 1))).to eq(Time.utc(2022, 4, 1))
    end

    context "when the schedule has already ended" do
      let(:ends_at) { Time.utc(2022, 3, 1) }

      it "reports nothing further" do
        expect(schedule.next_due_at(Time.utc(2023, 1, 1))).to be_nil
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
      expect(schedule.next_due_at(end_on)).to eq(Time.utc(2028, 1, 21))
    end
  end
end
