# frozen_string_literal: true

require "rails_helper"

# The resume matrix next door varies one thing at a time. This one turns everything on at once:
# 200 back-to-back effective rates cycling through six cadences, 61 phases alternating between
# their own cadence override and none at all — so the cadence comes from the RATE half the time
# and from the PHASE the other half — read off month-end, leap-day and mid-month anchors in
# three timezones, both advance and arrears.
#
# The number that matters is the re-anchor count: over 30 in every shape, up to 122. Each one is
# a chance for a resumed walk to rebuild the wrong ruler, and a ruler rebuilt one day off
# reprices every cycle after it.
RSpec.describe Billing::RateCards::Schedule do
  cadences = [[1, :day], [2, :day], [1, :week], [2, :week], [1, :month], [3, :day]]

  def rate(effective_from, count, unit)
    Struct.new(:effective_from, :billing_interval_count, :billing_interval_unit).new(effective_from, count, unit)
  end

  def override(count, unit)
    Struct.new(:billing_interval_count, :billing_interval_unit).new(count, unit)
  end

  # Every four days, so no rate gets a full cycle to itself on the slower cadences and a change
  # can land anywhere inside a window rather than only on its boundary.
  let(:rates) do
    (0...200).map do |i|
      count, unit = cadences[i % cadences.size]
      rate(Time.utc(2026, 1, 1) + (i * 4).days, count, unit)
    end
  end

  # Alternating: an even phase has NO override, so the rate in force decides the cadence; an odd
  # one overrides it with a cadence deliberately out of step with the rates. Every phase is 2 to
  # 4 cycles long, so resuming lands inside an override phase as often as at its first cycle.
  let(:phases) do
    (0...60).map { |i|
      Billing::Phase.new(
        code: "p#{i}",
        billing_interval_cycle_count: 2 + (i % 3),
        rate_override: i.even? ? nil : override(*cadences[(i + 2) % cadences.size])
      )
    } + [Billing::Phase.new(code: nil, billing_interval_cycle_count: nil, rate_override: nil)]
  end

  let(:asked_at) { Time.utc(2027, 7, 1) }

  def build(timezone:, timing:, anchor:, resume_at: nil)
    described_class.new(
      anchor_date: anchor, starts_at: anchor.in_time_zone(timezone), timezone:,
      phases:, rates:, resume_at:, terms: Billing::Terms.new(timing:, prorated: true)
    )
  end

  def build_walker(timezone:, anchor:, **)
    Billing::RateCards::CycleWalker.new(
      anchor_date: anchor, starts_at: anchor.in_time_zone(timezone), timezone:, phases:, rates:
    )
  end

  def walk(from: nil, **shape)
    build_walker(**shape).walk_to(asked_at, from:)
  end

  def state_of(cycle)
    [cycle.started_at, cycle.calendar.anchor_date, cycle.calendar.interval, cycle.index]
  end

  def cycle_values(cycles)
    cycles.map do |cycle|
      [cycle.index, cycle.started_at, cycle.ended_at, cycle.phase.code,
        cycle.calendar.interval, cycle.calendar.anchor_date]
    end
  end

  def segment_values(segments)
    segments.map do |segment|
      [segment.cycle_index, segment.cycle_started_at, segment.started_at, segment.ended_at,
        segment.billing_at, segment.proration_ratio, segment.rate_phase_code,
        segment.rate.effective_from, segment.rate_override&.billing_interval_unit]
    end
  end

  shapes = [
    {timezone: "America/New_York", timing: :arrears, anchor: Date.new(2026, 1, 31)},
    {timezone: "America/New_York", timing: :advance, anchor: Date.new(2026, 1, 31)},
    {timezone: "Asia/Kolkata", timing: :arrears, anchor: Date.new(2024, 2, 29)},
    {timezone: "Europe/Paris", timing: :advance, anchor: Date.new(2026, 3, 15)}
  ]

  # A stress test that quietly stops stressing is worthless, so the shape is asserted before the
  # behaviour is. Thresholds are the measured values less a margin: if a future edit thins the
  # fixture, this fails instead of the suite passing vacuously.
  shapes.each do |shape|
    it "keeps stressing re-anchoring, every cadence and both override modes on #{shape[:anchor]} in #{shape[:timezone]}" do
      cycles = walk(**shape)
      inside_an_override = cycles.each_with_index.count do |cycle, n|
        cycle.phase.rate_override && n.positive? && cycles[n - 1].phase.code == cycle.phase.code
      end

      expect(cycles.size).to be > 50
      expect(cycles.map { it.calendar.anchor_date }.uniq.size).to be > 30
      expect(cycles.map { it.calendar.interval }.uniq.size).to eq(cadences.size)
      expect(cycles.map { it.phase.rate_override.nil? }.uniq).to match_array([true, false])
      expect(inside_an_override).to be > 15
    end
  end

  shapes.each do |shape|
    context "with #{shape[:timing]} on #{shape[:anchor]} in #{shape[:timezone]}" do
      # The jump skips from one cadence change to the next, so a fixture with 122 re-anchors is
      # where it has the most to get wrong. The walk is the oracle.
      it "lands on the state the walk carries, at every one of its cycles" do
        walker = build_walker(**shape)

        mismatches = walk(**shape).filter_map do |cycle|
          jumped = state_of(walker.resume(cycle.started_at))
          next if jumped == state_of(cycle)

          "at #{cycle.started_at}: jumped to #{jumped}, walk had #{state_of(cycle)}"
        end

        expect(mismatches).to be_empty
      end

      it "answers the same cycles whichever of them it resumes at" do
        full = walk(**shape)

        mismatches = full.each_index.filter_map do |n|
          resumed = walk(**shape, from: full[n].started_at)
          next if cycle_values(resumed) == cycle_values(full.drop(n))

          "resuming at #{n} of #{full.size}: got #{cycle_values(resumed).first}, " \
            "expected #{cycle_values(full.drop(n)).first}"
        end

        expect(mismatches).to be_empty
      end

      it "answers the same segments whichever cycle it resumes at" do
        cycles = walk(**shape)
        full = segment_values(build(**shape).segments_due_by(asked_at))

        mismatches = cycles.filter_map do |cycle|
          resumed = segment_values(build(**shape, resume_at: cycle.started_at).segments_due_by(asked_at))
          tail = full.select { |values| values.first >= cycle.index }
          next if resumed == tail

          "resuming at #{cycle.index}: got #{resumed.size} segments, expected #{tail.size}"
        end

        expect(mismatches).to be_empty
      end
    end
  end
end
