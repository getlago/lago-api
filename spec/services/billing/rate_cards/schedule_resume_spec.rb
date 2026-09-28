# frozen_string_literal: true

require "rails_helper"

# Resuming exists so a two-year-old weekly card does not walk a hundred cycles to answer a
# question about next week. It is only worth having if it is INDISTINGUISHABLE from the full
# walk, so nothing here asserts a value of its own: every example resumes at every cycle of
# every shape and compares the tail against walking from the start.
RSpec.describe Billing::RateCards::Schedule do
  def rate(effective_from, count, unit)
    Struct.new(:effective_from, :billing_interval_count, :billing_interval_unit).new(effective_from, count, unit)
  end

  def override(count, unit)
    Struct.new(:billing_interval_count, :billing_interval_unit).new(count, unit)
  end

  def phase(cycle_count, count, unit, code = nil)
    Billing::Phase.new(code:, billing_interval_cycle_count: cycle_count,
      rate_override: count && override(count, unit))
  end

  def build(shape, resume_at: nil)
    described_class.new(
      anchor_date: shape[:anchor], starts_at: shape[:starts_at], timezone: shape[:timezone],
      phases: shape[:phase_args].map { |args| phase(*args) },
      rates: shape[:rate_args].map { |args| rate(*args) },
      ends_at: shape[:ends_at], resume_at:,
      terms: Billing::Terms.new(timing: shape[:timing], prorated: shape.fetch(:prorated, true))
    )
  end

  def build_walker(shape)
    Billing::RateCards::CycleWalker.new(
      anchor_date: shape[:anchor], starts_at: shape[:starts_at], timezone: shape[:timezone],
      phases: shape[:phase_args].map { |args| phase(*args) },
      rates: shape[:rate_args].map { |args| rate(*args) }, ends_at: shape[:ends_at]
    )
  end

  def walk(shape, to: asked_at, from: nil)
    build_walker(shape).walk_to(to, from:)
  end

  # Far enough out that every shape has billed a run of cycles by then, including the yearly
  # override and the card whose first rate lands in May 2026.
  let(:asked_at) { Time.utc(2027, 6, 1) }

  # Everything the walk carries at a cycle, read off a cycle the full walk produced — the oracle
  # the jump is measured against. The ruler is compared by what it IS rather than by identity,
  # because an anchor that clamps and an anchor that does not are two different rulers.
  def state_of(cycle)
    [cycle.started_at, cycle.calendar.anchor_date, cycle.calendar.interval, cycle.index]
  end

  def fingerprint(cycles)
    cycles.map do |cycle|
      [cycle.index, cycle.started_at, cycle.ended_at,
        cycle.phase.code, cycle.phase.billing_interval_cycle_count,
        cycle.calendar.interval, cycle.calendar.anchor_date]
    end
  end

  anchors = {
    "month-end" => Date.new(2026, 1, 31),
    "leap day" => Date.new(2024, 2, 29),
    "mid-month" => Date.new(2026, 3, 15),
    # Havana springs forward AT MIDNIGHT, so 00:00 does not exist on this date and
    # `beginning_of_day` answers 01:00. That breaks the identity every other shape relies on —
    # that a ruler boundary is the local midnight of its anchor day — so a re-anchor lands on a
    # ruler that opens at a different instant than the cursor which built it.
    "a day whose midnight does not exist" => Date.new(2026, 3, 8)
  }

  rate_sets = {
    "one rate" => [[Time.utc(2025, 1, 1), 1, :month]],
    "two rates, same cadence" => [[Time.utc(2025, 1, 1), 1, :month], [Time.utc(2026, 4, 10), 1, :month]],
    "monthly then weekly" => [[Time.utc(2025, 1, 1), 1, :month], [Time.utc(2026, 4, 10), 1, :week]],
    "monthly, weekly, monthly" => [[Time.utc(2025, 1, 1), 1, :month], [Time.utc(2026, 3, 10), 1, :week],
      [Time.utc(2026, 6, 20), 1, :month]],
    "three cadences and a rate change" => [[Time.utc(2025, 1, 1), 2, :week], [Time.utc(2026, 2, 5), 1, :month],
      [Time.utc(2026, 5, 17), 3, :day], [Time.utc(2026, 6, 2), 3, :day]],
    "first rate lands after the card opens" => [[Time.utc(2026, 5, 1), 1, :month]]
  }

  phase_sets = {
    "one open phase" => [[nil, 1, :month]],
    "weekly intro then monthly" => [[3, 1, :week, "intro"], [nil, 1, :month]],
    "two bounded then open" => [[2, 1, :week, "a"], [2, 1, :month, "b"], [nil, 1, :month]],
    "phase override differs from every rate" => [[4, 2, :week, "odd"], [nil, 1, :year]]
  }

  shapes = anchors.flat_map do |anchor_name, anchor|
    rate_sets.flat_map do |rates_name, rate_args|
      phase_sets.flat_map do |phases_name, phase_args|
        [["UTC", :arrears], ["America/New_York", :advance], ["Asia/Kolkata", :arrears],
          ["America/Havana", :arrears]].map do |timezone, timing|
          {name: "#{anchor_name} / #{rates_name} / #{phases_name} / #{timezone} #{timing}",
           anchor:, timezone:, timing:, starts_at: anchor.in_time_zone(timezone) + 2.days,
           rate_args:, phase_args:}
        end
      end
    end
  end

  # The jump is a shortcut through the walk, so the walk itself is the only honest oracle: for
  # every cycle of every shape, jumping to it must land on exactly the state the walk carried
  # there. A wrong index picks the wrong phase; a wrong anchor moves every later boundary.
  it "lands on the state the walk carries, for every cycle of every shape" do
    mismatches = shapes.flat_map do |shape|
      walker = build_walker(shape)

      walk(shape).filter_map do |cycle|
        jumped = state_of(walker.resume(cycle.started_at))
        next if jumped == state_of(cycle)

        "#{shape[:name]}: jumping to #{cycle.started_at} gave #{jumped}, walk had #{state_of(cycle)}"
      end
    end

    expect(mismatches).to be_empty
  end

  # The walker accepts a plain array and sorts rates before finding the next change.
  # Handing it the same rates backwards must preserve both the full and resumed walks.
  it "does not care what order the rates were handed in" do
    shape = {anchor: Date.new(2026, 1, 31), starts_at: Time.utc(2026, 1, 31), timezone: "UTC",
             timing: :arrears, phase_args: [[nil, nil, nil]],
             rate_args: [[Time.utc(2025, 1, 1), 1, :month], [Time.utc(2026, 4, 12), 1, :week],
               [Time.utc(2026, 8, 3), 3, :day]]}
    backwards = shape.merge(rate_args: shape[:rate_args].reverse)
    ascending = walk(shape)

    expect(ascending.size).to be > 20
    expect(fingerprint(walk(backwards))).to eq(fingerprint(ascending))

    ascending.each do |cycle|
      expect(walk(backwards, from: cycle.started_at).map(&:index))
        .to eq(ascending.drop(ascending.index(cycle)).map(&:index))
    end
  end

  # An instant inside a cycle resumes at that WHOLE cycle, not at the instant — which is what
  # re-billing a period that was only partly billed asks for. The consumer's own clock can hold
  # a mid-cycle instant, because a cut cycle's slice bills on its cut.
  it "resumes at the whole cycle covering a mid-cycle instant" do
    shape = shapes.first
    full = walk(shape)
    inside = full[2].started_at + ((full[2].ended_at - full[2].started_at) / 2)

    expect(fingerprint(walk(shape, from: inside)))
      .to eq(fingerprint(full.drop(2)))
  end

  context "when querying explicit dates on a resumed schedule" do
    let(:shape) { shapes.first }
    let(:full) { build(shape) }
    let(:cycles) { walk(shape) }
    let(:resumed) { build(shape, resume_at: cycles[3].started_at) }

    it "finds the current billing date before, at and after the resume point" do
      cycles[1..4].each do |cycle|
        expected = full.billing_at_covering(cycle.started_at)

        expect(expected).not_to be_nil
        expect(resumed.billing_at_covering(cycle.started_at)).to eq(expected)
      end
    end

    it "finds the billing instant of a cycle before the resume point" do
      at = cycles[1].started_at + 1.day

      expect(resumed.billing_at_covering(at)).to eq(cycles[1].ended_at)
      expect(resumed.next_billing_at(after: at)).to eq(cycles[1].ended_at)
    end

    it "keeps the due listing resumed after answering a historical billing date query" do
      resumed.billing_at_covering(cycles[1].started_at)

      expect(resumed.segments_due_by(cycles[4].ended_at).map(&:cycle_index)).to eq([3, 4])
    end

    it "finds the first billing date when asked before the card began" do
      at = shape[:starts_at] - 1.year

      expect(resumed.billing_at_covering(at)).to eq(cycles.first.ended_at)
    end
  end

  # Reject invalid inputs during construction, before a caller checks result.success?
  # and starts querying the schedule.
  it "refuses an instant before the card's own start when it is built" do
    shape = shapes.first

    expect { build(shape, resume_at: shape[:starts_at] - 1.year) }
      .to raise_error(ArgumentError, /precedes the card's start/)
  end

  # The cross product above varies one dimension at a time and shares one plain shape. These are
  # the cases the engine's own specs are built on, each resumed at every cycle: if resuming holds
  # for the matrix but breaks a QA scenario or a terminated card, the matrix was the wrong shape.
  named_scenarios = {
    "X5: a month-end anchor clamping and returning to the 31st" =>
      {anchor: Date.new(2026, 1, 31), timezone: "UTC", timing: :arrears,
       rate_args: [[Time.utc(2025, 1, 1), 1, :month]], phase_args: [[nil, 1, :month]]},

    "X6b: a yearly anchor on a leap day" =>
      {anchor: Date.new(2024, 2, 29), timezone: "UTC", timing: :arrears,
       rate_args: [[Time.utc(2023, 1, 1), 1, :year]], phase_args: [[nil, 1, :year]]},

    "AN1: an anchor ahead of the card's start, opening a stub cycle" =>
      {anchor: Date.new(2026, 2, 20), starts_at: Time.utc(2026, 2, 3), timezone: "UTC",
       timing: :arrears, rate_args: [[Time.utc(2025, 1, 1), 1, :month]], phase_args: [[nil, 1, :month]]},

    # Arrears on a two-year cadence: the first cycle only falls due in 2028, so this one is
    # asked far enough out to have cycles at all.
    "a cadence longer than a year" =>
      {anchor: Date.new(2018, 1, 1), timezone: "UTC", timing: :arrears,
       rate_args: [[Time.utc(2017, 1, 1), 2, :year]], phase_args: [[nil, 2, :year]]},

    "decision #56: the first rate lands after the card opens" =>
      {anchor: Date.new(2026, 1, 1), starts_at: Time.utc(2026, 1, 15), timezone: "UTC",
       timing: :arrears, rate_args: [[Time.utc(2026, 4, 1), 1, :month]], phase_args: [[nil, 1, :month]]},

    "a termination cutting the last cycle short" =>
      {anchor: Date.new(2026, 1, 31), timezone: "UTC", timing: :arrears, ends_at: Time.utc(2026, 6, 17, 14, 30),
       rate_args: [[Time.utc(2025, 1, 1), 1, :month]], phase_args: [[nil, 1, :month]]},

    "a termination landing exactly on a boundary" =>
      {anchor: Date.new(2026, 1, 31), timezone: "UTC", timing: :arrears, ends_at: Time.utc(2026, 5, 31),
       rate_args: [[Time.utc(2025, 1, 1), 1, :month]], phase_args: [[nil, 1, :month]]},

    "a card that does not prorate" =>
      {anchor: Date.new(2026, 1, 31), timezone: "UTC", timing: :arrears, prorated: false,
       ends_at: Time.utc(2026, 6, 17), rate_args: [[Time.utc(2025, 1, 1), 1, :month]],
       phase_args: [[nil, 1, :month]]},

    "a spring-forward day as the anchor" =>
      {anchor: Date.new(2026, 3, 8), timezone: "America/New_York", timing: :advance,
       rate_args: [[Time.utc(2025, 1, 1), 1, :day]], phase_args: [[nil, 1, :day]]},

    "a fall-back day as the anchor" =>
      {anchor: Date.new(2026, 11, 1), timezone: "America/New_York", timing: :arrears,
       rate_args: [[Time.utc(2025, 1, 1), 1, :day]], phase_args: [[nil, 1, :day]]},

    "a half-hour timezone that also observes DST" =>
      {anchor: Date.new(2026, 4, 5), timezone: "Australia/Lord_Howe", timing: :arrears,
       rate_args: [[Time.utc(2025, 1, 1), 1, :week]], phase_args: [[nil, 1, :week]]},

    "a rate change landing mid-cycle, cutting it" =>
      {anchor: Date.new(2026, 1, 1), timezone: "UTC", timing: :arrears,
       rate_args: [[Time.utc(2025, 1, 1), 1, :month], [Time.utc(2026, 3, 14, 7, 5), 1, :month]],
       phase_args: [[nil, 1, :month]]},

    "a cadence change on a month-end card" =>
      {anchor: Date.new(2026, 1, 31), timezone: "UTC", timing: :arrears,
       rate_args: [[Time.utc(2025, 1, 1), 1, :month], [Time.utc(2026, 4, 12), 1, :week]],
       phase_args: [[nil, nil, nil]]}
  }

  named_scenarios.each do |name, base|
    it "answers the same tail resuming anywhere in #{name}" do
      shape = {starts_at: base[:anchor].in_time_zone(base[:timezone])}.merge(base)
      full = walk(shape)
      segments = segment_values(build(shape).segments_due_by(asked_at))

      expect(full).not_to be_empty

      mismatches = full.each_index.flat_map do |n|
        resumed = build(shape, resume_at: full[n].started_at)
        [
          ((fingerprint(walk(shape, from: full[n].started_at)) == fingerprint(full.drop(n))) ? nil : "cycles at #{n}"),
          ((segment_values(resumed.segments_due_by(asked_at)) ==
            segments.select { |values| values.first >= full[n].index }) ? nil : "segments at #{n}")
        ].compact
      end

      expect(mismatches).to be_empty
    end
  end

  it "answers the same tail whichever cycle it resumes at, across #{shapes.size} card shapes" do
    mismatches = shapes.flat_map do |shape|
      full = walk(shape)

      full.each_index.filter_map do |n|
        resumed = walk(shape, from: full[n].started_at)
        next if fingerprint(resumed) == fingerprint(full.drop(n))

        "#{shape[:name]}: resuming at #{n} of #{full.size} gave " \
          "#{fingerprint(resumed).first(2)}, expected #{fingerprint(full.drop(n)).first(2)}"
      end
    end

    expect(mismatches).to be_empty
  end

  # The segments are what reaches the database, so the equality has to hold there too: a cycle
  # that matched but sliced differently would bill the same periods at different prices.
  #
  # Compared by value rather than by object: each schedule is handed its own rate stubs, and
  # two stubs of the same shape are never `==` because Struct.new makes a fresh class each time.
  def segment_values(segments)
    segments.map do |segment|
      [segment.cycle_index, segment.cycle_started_at, segment.started_at, segment.ended_at,
        segment.billing_at, segment.proration_ratio, segment.rate_phase_code,
        segment.rate.effective_from, segment.rate_override&.billing_interval_unit]
    end
  end

  it "produces the same segments whichever cycle it resumes at" do
    mismatches = shapes.flat_map do |shape|
      cycles = walk(shape)
      full = segment_values(build(shape).segments_due_by(asked_at))

      cycles.filter_map do |cycle|
        resumed = segment_values(build(shape, resume_at: cycle.started_at).segments_due_by(asked_at))
        tail = full.select { |values| values.first >= cycle.index }
        next if resumed == tail

        "#{shape[:name]}: resuming at #{cycle.index} gave #{resumed.first(2)}, expected #{tail.first(2)}"
      end
    end

    expect(mismatches).to be_empty
  end

  # The point of resuming: the same answer, less work.
  it "walks only the cycles it was not given" do
    shape = {anchor: Date.new(2026, 1, 31), starts_at: Time.utc(2026, 1, 31), timezone: "UTC",
             timing: :arrears, phase_args: [[nil, 1, :month]], rate_args: [[Time.utc(2025, 1, 1), 1, :month]]}
    asked = Time.utc(2028, 1, 1)
    full = walk(shape, to: asked)
    resumed = walk(shape, to: asked, from: full[-3].started_at)

    expect(full.size).to be > 20
    expect(resumed.size).to eq(3)
    expect(resumed.first.index).to eq(full[-3].index)
  end

  it "skips a century of daily cycles without visiting them" do
    shape = {anchor: Date.new(1926, 1, 1), starts_at: Time.utc(1926, 1, 1), timezone: "UTC",
             timing: :arrears, phase_args: [[nil, nil, nil]],
             rate_args: [[Time.utc(1926, 1, 1), 1, :day]]}
    walker = build_walker(shape)
    allow(walker).to receive(:build_cycle).and_call_original

    cycles = walker.walk_to(Time.utc(2026, 1, 3), from: Time.utc(2026, 1, 1))

    expect(cycles.map(&:started_at)).to eq([Time.utc(2026, 1, 1), Time.utc(2026, 1, 2), Time.utc(2026, 1, 3)])
    expect(cycles.map(&:index)).to eq([36_525, 36_526, 36_527])
    # Build the initial cycle, jump to January 1, then visit January 2 and 3.
    expect(walker).to have_received(:build_cycle).at_most(4).times
  end

  # The measured hazard, kept as an absolute assertion rather than a comparison: a boundary is
  # NOT an anchor. Anchored Jan 31 the boundaries run Feb 28, Mar 31; re-anchored on the Feb 28
  # boundary they would run Mar 28, Apr 28, and a month-end card never gets its day back. So the
  # anchor of a run reaching back past the rows is the ruler #state_at arrived carrying, never
  # the cursor's own date.
  it "keeps a month-end card's day when it resumes from the clamped February cycle" do
    shape = {anchor: Date.new(2026, 1, 31), starts_at: Time.utc(2026, 1, 31), timezone: "UTC",
             timing: :arrears, phase_args: [[nil, 1, :month]], rate_args: [[Time.utc(2025, 1, 1), 1, :month]]}
    resumed = walk(shape, from: Time.utc(2026, 2, 28))

    expect(resumed.first.started_at).to eq(Time.utc(2026, 2, 28))
    expect(resumed.map(&:ended_at).first(3))
      .to eq([Time.utc(2026, 3, 31), Time.utc(2026, 4, 30), Time.utc(2026, 5, 31)])
  end

  # Unrelated to resuming: starts_at is floored to the start of its local day and ends_at is not,
  # so comparing the floored start let a card terminated BEFORE it began through — and it billed
  # the six hours between.
  it "refuses a card whose end precedes its raw start" do
    expect {
      described_class.new(anchor_date: Date.new(2026, 1, 31), starts_at: Time.utc(2026, 1, 31, 8),
        ends_at: Time.utc(2026, 1, 31, 6), timezone: "UTC",
        phases: [phase(nil, 1, :month)], rates: [rate(Time.utc(2025, 1, 1), 1, :month)],
        terms: Billing::Terms.new(timing: :arrears, prorated: true))
    }.to raise_error(ArgumentError, /precedes starts_at/)
  end
end
