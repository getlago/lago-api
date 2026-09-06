# frozen_string_literal: true

# The QA acceptance plan as a NAMED SCENARIO SET, driven at the date layer.
#
# `/private/tmp/.../scratchpad/engine/QA_PLAN.txt` was executed against staging on
# 2026-08-10..13 and the outputs recorded in it are what product signed off against. Its
# executable HTTP form (`spec/requests/api/v2/qa_plan/`, 127 examples) can only ever
# exercise whichever engine is wired in; this file encodes the same cases as pure date-layer
# inputs so that all THREE engines can be asked the plan's questions.
#
# Every case carries:
#   setup    — the card exactly as the plan's fixture builds it (baseline: fixed product,
#              standard 30.00, monthly, arrears, 5 units, so a full period bills 150.00)
#   window   — the window the plan asks for, and which of the two questions it asks
#   pinned   — what the plan PINS: the periods, which rate prices each, `billing_at`, which
#              segments share a `cycle_index`, and the proration ratio the recorded cents
#              imply (R3b's 7500 on a 15000 baseline is 15/30)
#
# Dates are the plan's own. Nothing is expressed as an offset from anything: month lengths
# and the leap day are the point of half these cases.
#
# CONVENTION. The plan records an INCLUSIVE `period_to` (2026-09-09T23:59:59Z). Every
# expectation below is written in the exclusive convention the engines use
# (2026-09-10T00:00:00Z), which is the one normalisation this whole comparison applies.
# Arrears `billing_at` is that same instant, so the plan's "issuing_date = period end"
# observation (QA_ACCEPTANCE BREAK 2) is a presentation question and is not judged here.

require Rails.root.join("spec/services/billing/parity/three_way_harness").to_s

module BillingParity
  module QaPlanSet
    # Fields of one expected segment. `cycle` is a LABEL, not an index: what the plan pins
    # is which segments share a cycle, never what the shared number is (the payload has
    # published 1-based since before this work, the plan captured 0-based).
    Expected = Data.define(:from, :to, :rate, :billing_at, :cycle, :ratio)

    # `mode` is how much of the answer the plan pins. `:exact` means the plan states the
    # whole list (an invoice-total array, a `.sole`, a full `map`); `:prefix` means it
    # asserts only the leading segments (`json[:cycles].first`, `.first(2)`, `.first(4)`)
    # and says nothing about what follows. Scoring a prefix assertion as an exact one would
    # fail all three engines on a window that legitimately reaches into the next cycle.
    #
    # `open` marks a case the plan itself left OPEN: it asked for a value to be recorded,
    # not for one to be met. Reported, never scored as a break.
    Case = Data.define(
      :id, :note, :timing, :prorated, :timezone, :starts_at, :anchor, :ends_at,
      :rates, :phases, :query, :from, :to, :pinned, :mode, :open
    )

    Row = Data.define(:kase, :answers, :matches, :details)

    Report = Data.define(:rows) do
      # Cases the plan actually pins an answer for. The two OPEN ones are reported with all
      # three answers and scored against neither engine's reading.
      def scored = rows.reject { it.kase.open }

      def open_rows = rows.select { it.kase.open }

      def matched(engine) = scored.count { it.matches.include?(engine) }

      def broken(engine) = scored.reject { it.matches.include?(engine) }

      def table
        rows.map do |row|
          {
            id: row.kase.id,
            record: row.kase.pinned.size,
            old: row.matches.include?(:old),
            new: row.matches.include?(:new),
            pr: row.matches.include?(:pr)
          }
        end
      end
    end

    # -----------------------------------------------------------------------------------
    # Shorthand for writing the plan down
    # -----------------------------------------------------------------------------------
    module DSL
      module_function

      def t(string) = Time.utc(*string.split(/[-T:Z ]/).reject(&:empty?).map(&:to_i))

      def seg(from, to, rate:, cycle:, ratio: 1r, billing_at: nil)
        Expected.new(from: t(from), to: t(to), rate:, cycle:, ratio: Rational(ratio),
          billing_at: t(billing_at || to))
      end

      # An advance segment falls due when it opens, an arrears one when it closes.
      def adv(from, to, rate:, cycle:, ratio: 1r)
        seg(from, to, rate:, cycle:, ratio:, billing_at: from)
      end
    end

    extend DSL

    BASE_RATE = ["v1", "2026-01-01", 1, "month"].freeze

    # rubocop:disable Metrics/ParameterLists
    def self.kase(id, note:, query:, from:, to:, pinned:, starts_at:, timing: "arrears",
      prorated: false, timezone: "UTC", anchor: nil, ends_at: nil, rates: [BASE_RATE],
      phases: [], mode: :exact, open: false)
      Case.new(
        id:, note:, timing:, prorated:, timezone:,
        starts_at: DSL.t(starts_at), anchor: Date.parse(anchor || starts_at[0, 10]),
        ends_at: ends_at && DSL.t(ends_at),
        rates:, phases:, query:, from: DSL.t(from), to: DSL.t(to), pinned:, mode:, open:
      )
    end
    # rubocop:enable Metrics/ParameterLists

    # The plan's Step 1 / Step 2 windows: `start_on` at local midnight, `end_on` at the last
    # instant of its day, which is what the controller builds from the two params.
    def self.day_end(date) = "#{date}T23:59:59"

    CASES = [
      # -- R: rate lifecycle -----------------------------------------------------------
      kase(
        "R1", note: "one cycle on the active rate; the later rate is not yet in force",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-09-10"),
        rates: [["rate_r1_v1", "2026-01-01", 1, "month"], ["rate_r1_v2", "2026-12-01", 1, "month"]],
        pinned: [seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "rate_r1_v1", cycle: :c0)]
      ),
      kase(
        "R2a", note: "no rate in force: cycles: [] and no document at all",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-09-10"),
        rates: [["rate_r2_v1", "2027-01-01", 1, "month"]],
        pinned: []
      ),
      kase(
        "R2b", note: "bills 1:1 once the window reaches the priced periods — two invoices",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2027-02-10"),
        rates: [["rate_r2_v1", "2027-01-01", 1, "month"]],
        pinned: [
          seg("2027-01-01T00:00:00", "2027-01-10T00:00:00", rate: "rate_r2_v1", cycle: :c4),
          seg("2027-01-10T00:00:00", "2027-02-10T00:00:00", rate: "rate_r2_v1", cycle: :c5)
        ]
      ),
      kase(
        "R3a", note: "rate change ON a boundary: three whole cycles, no split, 15000·15000·18000",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-11-10"),
        rates: [["rate_r3a_v1", "2026-01-01", 1, "month"], ["rate_r3a_v2", "2026-10-10", 1, "month"]],
        pinned: [
          seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "rate_r3a_v1", cycle: :c0),
          seg("2026-09-10T00:00:00", "2026-10-10T00:00:00", rate: "rate_r3a_v1", cycle: :c1),
          seg("2026-10-10T00:00:00", "2026-11-10T00:00:00", rate: "rate_r3a_v2", cycle: :c2)
        ]
      ),
      kase(
        "R3b", note: "rate change MID-period: 15000·7500·9000·18000 on FOUR distinct billing instants; " \
                     "the two slices share one cycle_index; 7500 on a 15000 baseline is 15/30",
        starts_at: "2026-08-10T00:00:00", prorated: true, query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-11-10"),
        rates: [["rate_r3b_v1", "2026-01-01", 1, "month"], ["rate_r3b_v2", "2026-09-25", 1, "month"]],
        pinned: [
          seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "rate_r3b_v1", cycle: :c0),
          seg("2026-09-10T00:00:00", "2026-09-25T00:00:00", rate: "rate_r3b_v1", cycle: :c1, ratio: Rational(15, 30)),
          seg("2026-09-25T00:00:00", "2026-10-10T00:00:00", rate: "rate_r3b_v2", cycle: :c1, ratio: Rational(15, 30)),
          seg("2026-10-10T00:00:00", "2026-11-10T00:00:00", rate: "rate_r3b_v2", cycle: :c2)
        ]
      ),
      # R3b asked at an instant INSIDE the cut cycle, which is where the PR's cycle-level
      # release gate and NEW's per-segment one can part company. Not a plan window: the plan
      # billed one wide overdue window. Recorded so the difference is visible either way.
      kase(
        "R3b-mid", open: true,
        note: "PROBE, not a plan window (the plan billed one wide overdue window). The same R3b card " \
              "asked four days after the cut, which is where a cycle-level release gate and a " \
              "per-segment one part company. Written down as the per-segment reading; scored as OPEN " \
              "because the QA record does not cover a mid-cycle query",
        starts_at: "2026-08-10T00:00:00", prorated: true, query: :due_by,
        from: "2026-08-10T00:00:00", to: "2026-09-29T00:00:00",
        rates: [["rate_r3b_v1", "2026-01-01", 1, "month"], ["rate_r3b_v2", "2026-09-25", 1, "month"]],
        pinned: [
          seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "rate_r3b_v1", cycle: :c0),
          seg("2026-09-10T00:00:00", "2026-09-25T00:00:00", rate: "rate_r3b_v1", cycle: :c1, ratio: Rational(15, 30))
        ]
      ),

      # -- CS1a: subscription starting now, 2x2x2 over timing x proration x anchor -------
      kase(
        "CS1a-1", note: "advance · no proration · anchor = start → 15000", timing: "advance",
        starts_at: "2026-08-10T00:00:00", mode: :prefix, query: :overlapping,
        from: "2026-08-10T00:00:00", to: day_end("2026-09-10"),
        pinned: [adv("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "v1", cycle: :c0)]
      ),
      kase(
        "CS1a-2", note: "advance · proration · anchor = start → 15000 (a whole period)",
        timing: "advance", prorated: true, starts_at: "2026-08-10T00:00:00", mode: :prefix, query: :overlapping,
        from: "2026-08-10T00:00:00", to: day_end("2026-09-10"),
        pinned: [adv("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "v1", cycle: :c0)]
      ),
      kase(
        "CS1a-3", note: "advance · no proration · anchor Sep 1 → stub Aug 10→Sep 1 at 15000",
        timing: "advance", starts_at: "2026-08-10T00:00:00", anchor: "2026-09-01", mode: :prefix, query: :overlapping,
        from: "2026-08-10T00:00:00", to: day_end("2026-09-10"),
        pinned: [
          adv("2026-08-10T00:00:00", "2026-09-01T00:00:00", rate: "v1", cycle: :c0),
          adv("2026-09-01T00:00:00", "2026-10-01T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "CS1a-4", note: "advance · proration · anchor Sep 1 → 10645 = 150 x 22/31",
        timing: "advance", prorated: true, starts_at: "2026-08-10T00:00:00", anchor: "2026-09-01",
        mode: :prefix, query: :overlapping, from: "2026-08-10T00:00:00", to: day_end("2026-09-10"),
        pinned: [
          adv("2026-08-10T00:00:00", "2026-09-01T00:00:00", rate: "v1", cycle: :c0, ratio: Rational(22, 31)),
          adv("2026-09-01T00:00:00", "2026-10-01T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "CS1a-5", note: "arrears · no proration · anchor = start → 15000",
        starts_at: "2026-08-10T00:00:00", mode: :prefix, query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-09-10"),
        pinned: [seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "v1", cycle: :c0)]
      ),
      kase(
        "CS1a-6", note: "arrears · proration · anchor = start → 15000",
        prorated: true, starts_at: "2026-08-10T00:00:00", mode: :prefix, query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-09-10"),
        pinned: [seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "v1", cycle: :c0)]
      ),
      kase(
        "CS1a-7", note: "arrears · no proration · anchor Sep 1 → stub at 15000",
        starts_at: "2026-08-10T00:00:00", anchor: "2026-09-01", mode: :prefix, query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-09-10"),
        pinned: [seg("2026-08-10T00:00:00", "2026-09-01T00:00:00", rate: "v1", cycle: :c0)]
      ),
      kase(
        "CS1a-8", note: "arrears · proration · anchor Sep 1 → 10645 = 150 x 22/31, unit 21.29",
        prorated: true, starts_at: "2026-08-10T00:00:00", anchor: "2026-09-01", mode: :prefix, query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-09-10"),
        pinned: [seg("2026-08-10T00:00:00", "2026-09-01T00:00:00", rate: "v1", cycle: :c0, ratio: Rational(22, 31))]
      ),

      # -- CS1b: backdated, the catch-up assertion --------------------------------------
      kase(
        "CS1b-5", note: "backdated Jun 10: every elapsed cycle its own invoice — 15000 · 15000",
        starts_at: "2026-06-10T00:00:00", query: :due_by,
        from: "2026-06-10T00:00:00", to: day_end("2026-08-10"),
        pinned: [
          seg("2026-06-10T00:00:00", "2026-07-10T00:00:00", rate: "v1", cycle: :c0),
          seg("2026-07-10T00:00:00", "2026-08-10T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "CS1b-7", note: "backdated with an anchor on the 1st, no proration → 15000 · 15000",
        starts_at: "2026-06-10T00:00:00", anchor: "2026-09-01", query: :due_by,
        from: "2026-06-10T00:00:00", to: day_end("2026-08-10"),
        pinned: [
          seg("2026-06-10T00:00:00", "2026-07-01T00:00:00", rate: "v1", cycle: :c0),
          seg("2026-07-01T00:00:00", "2026-08-01T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "CS1b-8", note: "the same, prorated: the stub is 10500 = 150 x 21/30 (the plan's MATRIX)",
        prorated: true, starts_at: "2026-06-10T00:00:00", anchor: "2026-09-01", query: :due_by,
        from: "2026-06-10T00:00:00", to: day_end("2026-08-10"),
        pinned: [
          seg("2026-06-10T00:00:00", "2026-07-01T00:00:00", rate: "v1", cycle: :c0, ratio: Rational(21, 30)),
          seg("2026-07-01T00:00:00", "2026-08-01T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),

      # -- CS1c: starting in the future --------------------------------------------------
      kase(
        "CS1c-1", note: "advance · no proration · anchor Sep 1 → Sep 1→Oct 1 at 15000",
        timing: "advance", starts_at: "2026-09-01T00:00:00", mode: :prefix, query: :overlapping,
        from: "2026-09-01T00:00:00", to: day_end("2026-10-15"),
        pinned: [
          adv("2026-09-01T00:00:00", "2026-10-01T00:00:00", rate: "v1", cycle: :c0),
          adv("2026-10-01T00:00:00", "2026-11-01T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "CS1c-2", note: "advance · proration · anchor Sep 1 → a whole period, 15000",
        timing: "advance", prorated: true, starts_at: "2026-09-01T00:00:00", mode: :prefix, query: :overlapping,
        from: "2026-09-01T00:00:00", to: day_end("2026-10-15"),
        pinned: [
          adv("2026-09-01T00:00:00", "2026-10-01T00:00:00", rate: "v1", cycle: :c0),
          adv("2026-10-01T00:00:00", "2026-11-01T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "CS1c-3", note: "advance · no proration · anchor Sep 15 → stub Sep 1→Sep 15 at 15000",
        timing: "advance", starts_at: "2026-09-01T00:00:00", anchor: "2026-09-15", mode: :prefix, query: :overlapping,
        from: "2026-09-01T00:00:00", to: day_end("2026-10-15"),
        pinned: [
          adv("2026-09-01T00:00:00", "2026-09-15T00:00:00", rate: "v1", cycle: :c0),
          adv("2026-09-15T00:00:00", "2026-10-15T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "CS1c-4", note: "advance · proration · anchor Sep 15 → 6774 = 150 x 14/31 (a 31-day denominator)",
        timing: "advance", prorated: true, starts_at: "2026-09-01T00:00:00", anchor: "2026-09-15",
        mode: :prefix, query: :overlapping, from: "2026-09-01T00:00:00", to: day_end("2026-10-15"),
        pinned: [
          adv("2026-09-01T00:00:00", "2026-09-15T00:00:00", rate: "v1", cycle: :c0, ratio: Rational(14, 31)),
          adv("2026-09-15T00:00:00", "2026-10-15T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "CS1c-5", note: "arrears · no proration · anchor Sep 1 → 15000",
        starts_at: "2026-09-01T00:00:00", mode: :prefix, query: :due_by,
        from: "2026-09-01T00:00:00", to: day_end("2026-10-15"),
        pinned: [seg("2026-09-01T00:00:00", "2026-10-01T00:00:00", rate: "v1", cycle: :c0)]
      ),
      kase(
        "CS1c-6", note: "arrears · proration · anchor Sep 1 → 15000",
        prorated: true, starts_at: "2026-09-01T00:00:00", mode: :prefix, query: :due_by,
        from: "2026-09-01T00:00:00", to: day_end("2026-10-15"),
        pinned: [seg("2026-09-01T00:00:00", "2026-10-01T00:00:00", rate: "v1", cycle: :c0)]
      ),
      kase(
        "CS1c-7", note: "arrears · no proration · anchor Sep 15 → stub at 15000",
        starts_at: "2026-09-01T00:00:00", anchor: "2026-09-15", mode: :prefix, query: :due_by,
        from: "2026-09-01T00:00:00", to: day_end("2026-10-15"),
        pinned: [
          seg("2026-09-01T00:00:00", "2026-09-15T00:00:00", rate: "v1", cycle: :c0),
          seg("2026-09-15T00:00:00", "2026-10-15T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "CS1c-8", note: "arrears · proration · anchor Sep 15 → 6774 = 150 x 14/31",
        prorated: true, starts_at: "2026-09-01T00:00:00", anchor: "2026-09-15", mode: :prefix, query: :due_by,
        from: "2026-09-01T00:00:00", to: day_end("2026-10-15"),
        pinned: [
          seg("2026-09-01T00:00:00", "2026-09-15T00:00:00", rate: "v1", cycle: :c0, ratio: Rational(14, 31)),
          seg("2026-09-15T00:00:00", "2026-10-15T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "CS1c-19d", note: "the pair QA re-verified 2026-08-13: a 19-day stub, 15000 vs 9194 = 150 x 19/31",
        prorated: true, starts_at: "2026-08-13T00:00:00", anchor: "2026-09-01", query: :due_by,
        from: "2026-08-13T00:00:00", to: day_end("2026-09-01"),
        pinned: [seg("2026-08-13T00:00:00", "2026-09-01T00:00:00", rate: "v1", cycle: :c0, ratio: Rational(19, 31))]
      ),

      # -- BC: the cycle matrix, all units x counts ---------------------------------------
      *[
        ["BCa", 1, "day", "2026-08-11T00:00:00", "2026-08-12T00:00:00"],
        ["BCb", 45, "day", "2026-09-24T00:00:00", "2026-11-08T00:00:00"],
        ["BCc", 1, "week", "2026-08-17T00:00:00", "2026-08-24T00:00:00"],
        ["BCd", 4, "week", "2026-09-07T00:00:00", "2026-10-05T00:00:00"],
        ["BCe", 3, "month", "2026-11-10T00:00:00", "2027-02-10T00:00:00"],
        ["BCf", 6, "month", "2027-02-10T00:00:00", "2027-08-10T00:00:00"],
        ["BCg", 1, "year", "2027-08-10T00:00:00", "2028-08-10T00:00:00"],
        ["BCh", 2, "year", "2028-08-10T00:00:00", "2030-08-10T00:00:00"]
      ].map do |label, count, unit, first_close, second_close|
        kase(
          label,
          note: "#{unit} x #{count}: exact boundaries, 15000 per period regardless of length; " \
                "the first invoice is dated #{first_close[0, 10]}",
          starts_at: "2026-08-10T00:00:00", query: :due_by,
          from: "2026-08-10T00:00:00", to: day_end(second_close[0, 10]),
          rates: [["rate_#{label.downcase}_v1", "2026-01-01", count, unit]],
          pinned: [
            seg("2026-08-10T00:00:00", first_close, rate: "rate_#{label.downcase}_v1", cycle: :c0),
            seg(first_close, second_close, rate: "rate_#{label.downcase}_v1", cycle: :c1)
          ]
        )
      end,

      # -- PH: rate phases ----------------------------------------------------------------
      kase(
        "PH1", note: "a 14-day trial phase then the card's monthly cadence: Aug 10→Aug 24, then Aug 24→Sep 24",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-09-24"),
        phases: [["trial", 1, 14, "day"], ["std", nil, nil, nil]],
        pinned: [
          seg("2026-08-10T00:00:00", "2026-08-24T00:00:00", rate: "v1", cycle: :c0),
          seg("2026-08-24T00:00:00", "2026-09-24T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "PH2", note: "trial x1 then intro x3 then std: five cycles, transitions on boundaries only",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-12-24"),
        phases: [["trial", 1, 14, "day"], ["intro", 3, nil, nil], ["std", nil, nil, nil]],
        pinned: [
          seg("2026-08-10T00:00:00", "2026-08-24T00:00:00", rate: "v1", cycle: :c0),
          seg("2026-08-24T00:00:00", "2026-09-24T00:00:00", rate: "v1", cycle: :c1),
          seg("2026-09-24T00:00:00", "2026-10-24T00:00:00", rate: "v1", cycle: :c2),
          seg("2026-10-24T00:00:00", "2026-11-24T00:00:00", rate: "v1", cycle: :c3),
          seg("2026-11-24T00:00:00", "2026-12-24T00:00:00", rate: "v1", cycle: :c4)
        ]
      ),
      kase(
        "PH3", note: "cadence switch between phases: 3 monthly then a yearly tail Nov 10 '26 → Nov 10 '27",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2027-11-10"),
        phases: [["monthly_start", 3, nil, nil], ["yearly_tail", nil, 1, "year"]],
        pinned: [
          seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "v1", cycle: :c0),
          seg("2026-09-10T00:00:00", "2026-10-10T00:00:00", rate: "v1", cycle: :c1),
          seg("2026-10-10T00:00:00", "2026-11-10T00:00:00", rate: "v1", cycle: :c2),
          seg("2026-11-10T00:00:00", "2027-11-10T00:00:00", rate: "v1", cycle: :c3)
        ]
      ),
      kase(
        "PH4", note: "the default tail re-resolves the card's newest rate: 15000 · 15000 · 18000",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-11-10"),
        rates: [["rate_ph4_v1", "2026-01-01", 1, "month"], ["rate_ph4_v2", "2026-10-10", 1, "month"]],
        phases: [["std", nil, nil, nil]],
        pinned: [
          seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "rate_ph4_v1", cycle: :c0),
          seg("2026-09-10T00:00:00", "2026-10-10T00:00:00", rate: "rate_ph4_v1", cycle: :c1),
          seg("2026-10-10T00:00:00", "2026-11-10T00:00:00", rate: "rate_ph4_v2", cycle: :c2)
        ]
      ),

      # -- AN: anchor x proration ----------------------------------------------------------
      kase(
        "AN1", note: "prorated stub Aug 20→Sep 1 = 5806 = 150 x 12/31, then the anchored period in full",
        prorated: true, starts_at: "2026-08-20T00:00:00", anchor: "2026-09-01", query: :due_by,
        from: "2026-08-20T00:00:00", to: day_end("2026-10-01"),
        pinned: [
          seg("2026-08-20T00:00:00", "2026-09-01T00:00:00", rate: "v1", cycle: :c0, ratio: Rational(12, 31)),
          seg("2026-09-01T00:00:00", "2026-10-01T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "AN2", note: "the same two cycles, unprorated: the stub is charged in full — 15000 + 15000",
        starts_at: "2026-08-20T00:00:00", anchor: "2026-09-01", query: :due_by,
        from: "2026-08-20T00:00:00", to: day_end("2026-10-01"),
        pinned: [
          seg("2026-08-20T00:00:00", "2026-09-01T00:00:00", rate: "v1", cycle: :c0),
          seg("2026-09-01T00:00:00", "2026-10-01T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),

      # -- X: additional coverage ----------------------------------------------------------
      kase(
        "X1p", open: true,
        note: "termination Sep 25 is EXCLUSIVE: the final window is Sep 10→Sep 25, ratio 15/30 → 7500. " \
              "The plan left this OPEN — its written expected column says 80.00 / 16 days (16/30), and it " \
              "asked for whichever the code does to be recorded. Scored against the exclusive reading that " \
              "QA_ACCEPTANCE measured and pinned; the 16/30 answer is the plan's other reading, not a break",
        prorated: true, starts_at: "2026-08-10T00:00:00", ends_at: "2026-09-25T00:00:00",
        query: :overlapping, from: "2026-08-10T00:00:00", to: "2026-09-25T00:00:00",
        pinned: [
          seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "v1", cycle: :c0),
          seg("2026-09-10T00:00:00", "2026-09-25T00:00:00", rate: "v1", cycle: :c1, ratio: Rational(15, 30))
        ]
      ),
      kase(
        "X1f", note: "the same termination on an unprorated card: the truncated window is charged whole",
        starts_at: "2026-08-10T00:00:00", ends_at: "2026-09-25T00:00:00",
        query: :overlapping, from: "2026-08-10T00:00:00", to: "2026-09-25T00:00:00",
        pinned: [
          seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "v1", cycle: :c0),
          seg("2026-09-10T00:00:00", "2026-09-25T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "X3", note: "contract C3: one invoice per cycle covered by the window — three cycles",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-11-10"),
        pinned: [
          seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "v1", cycle: :c0),
          seg("2026-09-10T00:00:00", "2026-10-10T00:00:00", rate: "v1", cycle: :c1),
          seg("2026-10-10T00:00:00", "2026-11-10T00:00:00", rate: "v1", cycle: :c2)
        ]
      ),
      kase(
        "X3-pre", note: "a window opening before started_at bills no pre-start period",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-06-01T00:00:00", to: day_end("2026-09-10"),
        pinned: [seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "v1", cycle: :c0)]
      ),
      kase(
        "X5", note: "month-end clamping: Aug 31 clamps to Sep 30 / Oct 31 and RETURNS to the 31st — no drift",
        starts_at: "2026-08-31T00:00:00", query: :due_by,
        from: "2026-08-31T00:00:00", to: day_end("2026-12-31"),
        pinned: [
          seg("2026-08-31T00:00:00", "2026-09-30T00:00:00", rate: "v1", cycle: :c0),
          seg("2026-09-30T00:00:00", "2026-10-31T00:00:00", rate: "v1", cycle: :c1),
          seg("2026-10-31T00:00:00", "2026-11-30T00:00:00", rate: "v1", cycle: :c2),
          seg("2026-11-30T00:00:00", "2026-12-31T00:00:00", rate: "v1", cycle: :c3)
        ]
      ),
      kase(
        "X6a", note: "leap day, monthly: 2028-01-31 → 2028-02-29, then 2028-02-29 → 2028-03-31",
        starts_at: "2028-01-31T00:00:00", query: :due_by,
        from: "2028-01-31T00:00:00", to: day_end("2028-03-31"),
        pinned: [
          seg("2028-01-31T00:00:00", "2028-02-29T00:00:00", rate: "v1", cycle: :c0),
          seg("2028-02-29T00:00:00", "2028-03-31T00:00:00", rate: "v1", cycle: :c1)
        ]
      ),
      kase(
        "X6b", note: "yearly anchored on Feb 29: clamps to Feb 28 for 2029/2030/2031 and RETURNS to Feb 29 in 2032",
        starts_at: "2028-02-29T00:00:00", query: :due_by,
        from: "2028-02-29T00:00:00", to: day_end("2033-03-01"),
        rates: [["rate_x6b_v1", "2026-01-01", 1, "year"]],
        pinned: [
          seg("2028-02-29T00:00:00", "2029-02-28T00:00:00", rate: "rate_x6b_v1", cycle: :c0),
          seg("2029-02-28T00:00:00", "2030-02-28T00:00:00", rate: "rate_x6b_v1", cycle: :c1),
          seg("2030-02-28T00:00:00", "2031-02-28T00:00:00", rate: "rate_x6b_v1", cycle: :c2),
          seg("2031-02-28T00:00:00", "2032-02-29T00:00:00", rate: "rate_x6b_v1", cycle: :c3),
          seg("2032-02-29T00:00:00", "2033-02-28T00:00:00", rate: "rate_x6b_v1", cycle: :c4)
        ]
      ),
      # X7 and X8 are about two cards on one subscription. The date layer sees one card at a
      # time, so what the plan pins about them that this layer decides is each card's own
      # stream and the instant it falls due — same instant means one document (X7), a yearly
      # card silent at a monthly boundary means one fee (X8).
      kase(
        "X7-seat", note: "two cards, one invoice: the seat card falls due on the same instant as the support card",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-09-10"),
        pinned: [seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "v1", cycle: :c0)]
      ),
      kase(
        "X7-support", note: "the support card, monthly, same anchor: the same window and the same due instant",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-09-10"),
        rates: [["rate_x7_support_v1", "2026-01-01", 1, "month"]],
        pinned: [seg("2026-08-10T00:00:00", "2026-09-10T00:00:00", rate: "rate_x7_support_v1", cycle: :c0)]
      ),
      kase(
        "X8-yearly", note: "the yearly card is silent at the monthly boundary: nothing due by Sep 10, and no proration of it",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-08-10T00:00:00", to: day_end("2026-09-10"),
        rates: [["rate_x8_support_v1", "2026-01-01", 1, "year"]],
        pinned: []
      ),
      kase(
        "X8-monthly", note: "the monthly card over a full year: twelve periods at 15000",
        starts_at: "2026-08-10T00:00:00", query: :due_by,
        from: "2026-08-10T00:00:00", to: "2027-08-10T00:00:00",
        pinned: (0..11).map do |index|
          from = Date.new(2026, 8, 10) >> index
          to = Date.new(2026, 8, 10) >> (index + 1)
          seg("#{from}T00:00:00", "#{to}T00:00:00", rate: "v1", cycle: :"c#{index}")
        end
      )
    ].freeze

    # -----------------------------------------------------------------------------------
    # Driving one case through all three engines
    # -----------------------------------------------------------------------------------
    class Run
      TIMEOUT = BillingParity::Runner::SCENARIO_TIMEOUT

      def initialize(kase)
        @kase = kase
      end

      attr_reader :kase

      def rate_card
        @rate_card ||= FakeRateCard.new(billing_timing: kase.timing, proration: kase.prorated)
      end

      def rates
        @rates ||= kase.rates.map do |code, effective_from, count, unit|
          FakeRate.new(
            code:, effective_from: Time.zone.parse("#{effective_from} 00:00:00").utc,
            billing_interval_count: count, billing_interval_unit: unit,
            rate_card:, properties: {"code" => code}
          )
        end
      end

      # Every configured phase carries an override whose CODE is the phase's own, because
      # `rate_phase_code` is what the plan pins and the code is the only channel the date
      # layer exposes it through. A phase that only changes the price leaves both interval
      # fields nil, which changes no arithmetic in any of the three engines.
      def phases
        @phases ||= kase.phases.each_with_index.map do |(code, cycle_count, count, unit), index|
          FakeRatePhase.new(
            position: index + 1, code:, billing_interval_cycle_count: cycle_count,
            rate_override: FakeOverride.new(code:, billing_interval_count: count,
              billing_interval_unit: unit, properties: {"code" => code})
          )
        end
      end

      def subscription_rate_card
        @subscription_rate_card ||= FakeSubscriptionRateCard.new(
          billing_anchor_date: kase.anchor, card_started_at: kase.starts_at, rate_card:
        )
      end

      def answers
        ThreeWay::ENGINES.index_with { |engine| guarded { send(:"#{engine}_answer") } }
      end

      # ---- NEW -------------------------------------------------------------------------
      def new_schedule
        @new_schedule ||= Billing::Schedule.new(
          anchor_date: kase.anchor,
          timezone: kase.timezone,
          starts_at: kase.starts_at,
          ends_at: kase.ends_at,
          terms: Billing::Terms.new(timing: kase.timing.to_sym, prorated: kase.prorated),
          rates: Billing::RateTimeline.new(rates),
          phases: phases.map do |phase|
            Billing::Schedule::Phase.new(position: phase.position, cycle_count: phase.billing_interval_cycle_count,
              code: phase.code, override: phase.rate_override)
          end,
          anchor_policy: Billing::AnchorPolicy::Realigning
        )
      end

      def new_answer
        segments = case kase.query
        when :due_by then new_schedule.segments_due_by(kase.to)
        when :overlapping then new_schedule.segments_overlapping(kase.from..kase.to)
        end

        ThreeWay.windows(normalise_new(segments))
      end

      def normalise_new(segments)
        segments.map do |segment|
          Window.new(
            started_at: segment.started_at.utc, ended_at: segment.ended_at.utc,
            cycle_started_at: segment.cycle_started_at.utc, cycle_index: segment.cycle_index,
            billing_at: segment.billing_at.utc, rate_code: segment.rate.code,
            override_code: segment.rate_override&.code, proration_ratio: segment.proration_ratio
          )
        end
      end

      # ---- PR --------------------------------------------------------------------------
      def pr_driver
        @pr_driver ||= ThreeWay::PrDriver.new(
          anchor_date: kase.anchor, timezone: kase.timezone, starts_at: kase.starts_at,
          ends_at: kase.ends_at, timing: kase.timing, prorated: kase.prorated,
          rates:, phases:, realign: true
        )
      end

      def pr_answer
        windows = case kase.query
        when :due_by then pr_driver.segments_due_by(kase.to)
        when :overlapping then pr_driver.segments_overlapping(kase.from..kase.to)
        end

        ThreeWay.windows(windows)
      end

      # ---- OLD -------------------------------------------------------------------------
      #
      # `exclude_out_of_range` is the old flag `segments_due_by` replaced, and `termination`
      # is how the old engine was told a card ends — which is what `segments_overlapping`
      # replaced. Each query is given the flags the old engine was actually driven with.
      def old_answer
        result = LegacyEngine::BillingPeriods::DatesService.from_subscription_rate_card(
          subscription_rate_card,
          rates:,
          range: kase.from..kase.to,
          rate_phases: LegacyEngine::SubscriptionRateCards::ResolveRatePhasesService::RatePhases.new(phases:),
          options: LegacyEngine::BillingPeriods::DatesService::Options.new(
            timezone: kase.timezone,
            exclude_out_of_range: kase.query == :due_by,
            realign_billing_anchor: true,
            termination: !kase.ends_at.nil?
          )
        )

        ThreeWay.windows(normalise_old(result.periods))
      end

      def normalise_old(periods)
        periods.map do |period|
          Window.new(
            started_at: period.period_from.utc,
            ended_at: exclusive(period.period_to),
            cycle_started_at: period.cycle.period_from.utc,
            cycle_index: period.cycle.index,
            billing_at: period.rate.rate_card.advance? ? period.billing_at.utc : exclusive(period.billing_at),
            rate_code: period.rate.code,
            override_code: period.rate_override&.code,
            proration_ratio: period.proration_ratio
          )
        end
      end

      def exclusive(time) = Time.zone.at(time.utc.to_r + Rational(1, 1_000_000_000)).utc

      def guarded
        Timeout.timeout(TIMEOUT) { yield }
      rescue Timeout::Error
        ThreeWay.failure("did not terminate within #{TIMEOUT}s")
      rescue Exception => e # rubocop:disable Lint/RescueException
        ThreeWay.failure("#{e.class}: #{e.message}")
      end
    end

    # -----------------------------------------------------------------------------------
    # Judging an engine against the QA record
    # -----------------------------------------------------------------------------------
    module Judge
      module_function

      # An engine matches the record when it produces exactly the pinned segments, in order,
      # with the pinned rate, the pinned due instant, the pinned proration ratio, and the
      # pinned cycle GROUPING (which segments share a cycle, not what the shared number is).
      def failures(kase, answer)
        pinned = kase.pinned
        return ["could not answer: #{answer.failure}"] if answer.failed?

        got = answer.windows
        if kase.mode == :prefix
          return ["#{got.size} segments, the record pins at least #{pinned.size}"] if got.size < pinned.size

          got = got.first(pinned.size)
        elsif got.size != pinned.size
          return ["#{got.size} segments, the record pins #{pinned.size}"]
        end

        pinned.zip(got).each_with_index.flat_map { |(want, have), index| field_failures(want, have, index) } +
          grouping_failures(pinned, got)
      end

      def field_failures(want, have, index)
        checks = {
          "started_at" => [want.from, have.started_at],
          "ended_at" => [want.to, have.ended_at],
          "billing_at" => [want.billing_at, have.billing_at]
        }

        out = checks.filter_map do |name, (expected, actual)|
          next if ThreeWay.close?(expected, actual)

          "segment #{index} #{name}: #{fmt(actual)}, the record pins #{fmt(expected)}"
        end

        out << "segment #{index} rate: #{have.rate_code}, the record pins #{want.rate}" if have.rate_code != want.rate
        unless ThreeWay.ratio_close?(want.ratio, have.proration_ratio)
          out << "segment #{index} proration_ratio: #{have.proration_ratio} (#{have.proration_ratio.to_f.round(6)}), " \
                 "the record pins #{want.ratio} (#{want.ratio.to_f.round(6)})"
        end
        out
      end

      # The plan pins which segments share a cycle, never the number itself.
      def grouping_failures(pinned, got)
        want = pinned.map(&:cycle).each_with_index.group_by(&:first).values.map { |pairs| pairs.map(&:last) }.sort
        have = got.map(&:cycle_index).each_with_index.group_by(&:first).values.map { |pairs| pairs.map(&:last) }.sort
        return [] if want == have

        ["cycle grouping #{have.inspect}, the record pins #{want.inspect}"]
      end

      def fmt(time) = time&.utc&.strftime("%Y-%m-%d %H:%M:%S")
    end

    module_function

    REPORT = Concurrent::Map.new

    def report
      REPORT.fetch_or_store(:qa) { build }
    end

    def build
      rows = []

      BillingParity.travel_to(FROZEN_NOW) do
        CASES.each do |kase|
          answers = Run.new(kase).answers
          details = answers.transform_values { |answer| Judge.failures(kase, answer) }
          rows << Row.new(kase:, answers:, matches: details.select { |_, v| v.empty? }.keys, details:)
        end
      end

      Report.new(rows:)
    end
  end
end
