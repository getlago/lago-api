# frozen_string_literal: true

# Differential harness: drives the OLD engine (vendored under spec/legacy_engine as
# LegacyEngine::) and the NEW engine (app/services/billing) over the same inputs and reports
# every disagreement, classified.
#
# Nothing here touches ActiveRecord. Both engines read a handful of messages off their inputs
# (`effective_from`, `billing_interval_count/unit`, `billing_anchor_date`, `card_started_at`,
# `proration?`, `rate_card.advance?`), so Structs stand in for the models and a scenario costs
# microseconds instead of a dozen INSERTs.

require "timeout"
require "active_support/testing/time_helpers"

LEGACY_ENGINE_ROOT = Rails.root.join("spec/legacy_engine")
%w[
  utils/datetime
  subscription_rate_cards/resolve_rate_phases_service
  billing_periods/boundaries
  billing_periods/dates_service
  billing_periods/first_period_service
  billing_periods/dates/base_service
  billing_periods/dates/advance_service
  billing_periods/dates/arrears_service
  billing_periods/dates/termination_service
].each { |file| require LEGACY_ENGINE_ROOT.join(file).to_s }

module BillingParity
  # The clock is frozen far in the past of every scenario so that the old engine's
  # `max(boundary, Time.current)` in Period#billing_at is always a no-op and billing_at is
  # directly comparable. R38's clamp is characterised separately, not fuzzed here.
  FROZEN_NOW = Time.utc(2000, 1, 1)

  # Windows are compared at 1 microsecond. The old engine ends a period at the last instant it
  # covers, with two different last instants: `.end_of_day` lands on .999999999 and
  # `moment_before` lands on -1us. Adding one nanosecond turns the first into the exclusive end
  # exactly and the second into 999ns short of it, so the tolerance absorbs the second shape and
  # nothing else: the smallest real disagreement the old engine can produce is a whole second.
  END_TOLERANCE = Rational(1, 1_000_000)
  RATIO_TOLERANCE = 1e-9

  CADENCES = [
    [1, "day"], [15, "day"], [1, "week"], [2, "week"],
    [1, "month"], [3, "month"], [6, "month"], [1, "year"]
  ].freeze

  TIMINGS = %w[advance arrears].freeze
  ANCHOR_KINDS = %i[before equal after day31 feb29].freeze
  START_TIMES_OF_DAY = %i[midnight mid_morning one_second_before_midnight].freeze
  RATE_PLANS = %i[none midnight_change midday_change two_same_day two_diff_days cadence_change starts_after_card].freeze
  PHASE_PLANS = %i[none one_bounded two_bounded count_only unit_only both].freeze
  TIMEZONES = ["UTC", "America/New_York", "Europe/Paris", "Asia/Kolkata", "Pacific/Auckland", "Asia/Tokyo"].freeze
  ENDS_KINDS = %i[none mid_cycle on_boundary before_first_close].freeze
  SPANS = %i[normal spring_forward_north fall_back_north spring_forward_south fall_back_south].freeze
  QUERIES = %i[segments_overlapping segments_due_by next_billing_at].freeze

  # Where each span starts, chosen so that a daily or weekly walk crosses the transition and a
  # monthly one contains it.
  SPAN_START_DATES = {
    normal: Date.new(2026, 5, 12),
    spring_forward_north: Date.new(2026, 3, 1),   # US Mar 8, EU Mar 29
    fall_back_north: Date.new(2026, 10, 20),      # EU Oct 25, US Nov 1
    spring_forward_south: Date.new(2026, 9, 15),  # Auckland Sep 27
    fall_back_south: Date.new(2026, 3, 20)        # Auckland Apr 5
  }.freeze

  CYCLES_WALKED = 8

  FakeRateCard = Struct.new(:billing_timing, :proration, keyword_init: true) do
    def advance? = billing_timing.to_s == "advance"

    def arrears? = !advance?

    def proration? = proration
  end

  FakeRate = Struct.new(
    :code, :effective_from, :billing_interval_count, :billing_interval_unit, :rate_card, :properties,
    keyword_init: true
  )

  FakeOverride = Struct.new(:code, :billing_interval_count, :billing_interval_unit, :properties, keyword_init: true)

  FakeRatePhase = Struct.new(:position, :code, :billing_interval_cycle_count, :rate_override, keyword_init: true)

  FakeSubscriptionRateCard = Struct.new(:billing_anchor_date, :card_started_at, :rate_card, keyword_init: true) do
    def proration? = rate_card.proration?
  end

  # There is no `policy` axis: `Billing::AnchorPolicy::Realigning` is the only mode that
  # ships (LAGO-1766), so every scenario runs under it and the old engine is driven with
  # `realign_billing_anchor: true` to match. The fixed-anchor half of the space, and the
  # old-vs-new comparison of it, are gone with the mode.
  Scenario = Data.define(
    :id, :timing, :cadence, :anchor_kind, :start_tod, :rate_plan, :phase_plan,
    :timezone, :ends_kind, :span, :prorated
  ) do
    def to_h_compact
      {
        timing:, cadence: cadence.join(" "), anchor: anchor_kind, start_tod:, rates: rate_plan,
        phases: phase_plan, tz: timezone, ends: ends_kind, span:, prorated:
      }
    end

    def describe
      to_h_compact.map { |k, v| "#{k}=#{v}" }.join(" ")
    end
  end

  # One normalised window, whichever engine produced it. Every field is directly comparable
  # except `ended_at`, which the builders have already converted to the exclusive convention.
  Window = Data.define(
    :started_at, :ended_at, :cycle_started_at, :cycle_index, :billing_at,
    :rate_code, :override_code, :proration_ratio
  ) do
    def to_s
      "[#{fmt(started_at)}, #{fmt(ended_at)}) cycle=#{cycle_index}@#{fmt(cycle_started_at)} " \
        "bill=#{fmt(billing_at)} rate=#{rate_code} override=#{override_code.inspect} " \
        "ratio=#{proration_ratio.is_a?(Rational) ? "#{proration_ratio} (#{proration_ratio.to_f.round(6)})" : proration_ratio.round(6)}"
    end

    def fmt(time)
      return "nil" if time.nil?

      time.utc.strftime("%Y-%m-%d %H:%M:%S.%6N")
    end
  end

  Divergence = Data.define(:classification, :mechanism, :field, :detail)

  Outcome = Data.define(:scenario, :query, :old, :new, :divergences, :old_error, :new_error, :comparable)

  # ---------------------------------------------------------------------------------------
  # Building the concrete inputs of one scenario
  # ---------------------------------------------------------------------------------------
  class Inputs
    attr_reader :scenario

    def initialize(scenario)
      @scenario = scenario
    end

    def zone = @zone ||= Time.find_zone!(scenario.timezone)

    def count = scenario.cadence.first

    def unit = scenario.cadence.last

    def start_date = SPAN_START_DATES.fetch(scenario.span)

    def started_at
      @started_at ||= case scenario.start_tod
      when :midnight then zone.local(start_date.year, start_date.month, start_date.day, 0, 0, 0)
      when :mid_morning then zone.local(start_date.year, start_date.month, start_date.day, 9, 17, 0)
      when :one_second_before_midnight then zone.local(start_date.year, start_date.month, start_date.day, 23, 59, 59)
      end
    end

    # Both engines floor the walk to the start of the card's local day; the scaffolding needs
    # the same instant to lay rate changes and ends_at on.
    def cursor_origin = @cursor_origin ||= started_at.in_time_zone(zone).beginning_of_day

    def anchor_date
      @anchor_date ||= case scenario.anchor_kind
      when :before then start_date - 20
      when :equal then start_date
      when :after then start_date + 12
      when :day31 then Date.new(start_date.year, 1, 31)
      when :feb29 then Date.new(2024, 2, 29)
      end
    end

    def advance_steps(time, steps)
      units = steps * count

      case unit
      when "day" then time + units.days
      when "week" then time + units.weeks
      when "month" then time + units.months
      when "year" then time + units.years
      end
    end

    def rate_card = @rate_card ||= FakeRateCard.new(billing_timing: scenario.timing, proration: scenario.prorated)

    # Every rate change is placed against the card's own local calendar, two cadence steps in,
    # so it lands inside the walked span for every cadence from a day to a year.
    def change_day = @change_day ||= advance_steps(cursor_origin, 2).in_time_zone(zone).beginning_of_day

    def rates
      @rates ||= begin
        base = build_rate("base", cursor_origin - 1.day, count, unit)

        case scenario.rate_plan
        when :none
          [base]
        when :midnight_change
          [base, build_rate("mid", change_day, count, unit)]
        when :midday_change
          [base, build_rate("mid", change_day + 13.hours + 37.minutes, count, unit)]
        when :two_same_day
          [base, build_rate("a", change_day + 9.hours, count, unit), build_rate("b", change_day + 17.hours, count, unit)]
        when :two_diff_days
          [base, build_rate("a", change_day + 9.hours, count, unit),
            build_rate("b", advance_steps(change_day, 1) + 17.hours, count, unit)]
        when :cadence_change
          [base, build_rate("mid", change_day, *other_cadence)]
        when :starts_after_card
          [build_rate("late", change_day, count, unit)]
        end
      end
    end

    # A cadence a rate change can switch TO that is always different from the card's own.
    def other_cadence
      (unit == "week") ? [1, "month"] : [2, "week"]
    end

    def build_rate(code, effective_from, interval_count, interval_unit)
      FakeRate.new(
        code:,
        effective_from: effective_from.utc,
        billing_interval_count: interval_count,
        billing_interval_unit: interval_unit,
        rate_card:,
        properties: {"code" => code}
      )
    end

    def phase_specs
      case scenario.phase_plan
      when :none then []
      when :one_bounded then [[2, 2, nil]]
      when :two_bounded then [[2, 2, nil], [3, nil, "week"]]
      when :count_only then [[3, 2, nil]]
      when :unit_only then [[3, nil, "week"]]
      when :both then [[3, 2, "week"]]
      end
    end

    def phases
      @phases ||= phase_specs.each_with_index.map do |(cycle_count, override_count, override_unit), index|
        FakeRatePhase.new(
          position: index + 1,
          code: "phase#{index + 1}",
          billing_interval_cycle_count: cycle_count,
          rate_override: FakeOverride.new(
            code: "ov#{index + 1}",
            billing_interval_count: override_count,
            billing_interval_unit: override_unit,
            properties: {"code" => "ov#{index + 1}"}
          )
        )
      end
    end

    def subscription_rate_card
      @subscription_rate_card ||= FakeSubscriptionRateCard.new(
        billing_anchor_date: anchor_date,
        card_started_at: started_at.utc,
        rate_card:
      )
    end

    # The old engine reads its range begin through `to_date.beginning_of_day.utc`, so starting
    # two days early keeps `cycle_due?`'s `next_billing_at > range_begin` from silently
    # dropping the first cycle. The comparison is about the walk, not about that filter.
    def walk_begin = @walk_begin ||= [cursor_origin, anchor_date.in_time_zone(zone).beginning_of_day].min - 2.days

    def walk_end = @walk_end ||= advance_steps(cursor_origin, CYCLES_WALKED)

    # Halfway through the WALK, not halfway through the range: `walk_begin` reaches back to the
    # anchor, which for a Jan-31 or Feb-29 anchor can be months before the card ever starts, and
    # a probe there would ask both engines about a schedule that has not begun.
    def midpoint = @midpoint ||= Time.zone.at((cursor_origin.to_r + walk_end.to_r) / 2).utc

    # The legacy ruler, used only as neutral scaffolding to find a real boundary for the
    # `ends_at` axis. Using the OLD engine's arithmetic here keeps the axis from being defined
    # by the implementation under test.
    def legacy_boundaries
      @legacy_boundaries ||= LegacyEngine::BillingPeriods::Boundaries.new(
        billing_anchor_date: anchor_date, interval_count: count, interval_unit: unit, timezone: scenario.timezone
      )
    end

    def first_boundary_after_start
      index = legacy_boundaries.index_on_or_before(cursor_origin.in_time_zone(zone))
      legacy_boundaries.at(index + 1).utc
    end

    def ends_at
      @ends_at ||= case scenario.ends_kind
      when :none then nil
      when :mid_cycle then (advance_steps(cursor_origin, 3) + 7.hours + 13.minutes).utc
      when :on_boundary
        boundary = first_boundary_after_start
        3.times { boundary = advance_steps(boundary, 1) }
        boundary.utc
      when :before_first_close
        Time.zone.at((cursor_origin.to_r + first_boundary_after_start.to_r) / 2).utc
      end
    end

    def terminating? = !ends_at.nil?

    # The cadence a given cycle runs at, replayed from the scenario's own configuration. Used
    # ONLY to explain a divergence - never as an oracle - so that "the cadence changed here" is
    # a checked fact rather than "this scenario has phases in it somewhere".
    def effective_interval(cycle_index, cycle_started_at)
      phase = phase_for_cycle(cycle_index)
      rate = rates.select { it.effective_from <= cycle_started_at }.max_by(&:effective_from) || rates.min_by(&:effective_from)
      override = phase&.rate_override

      [override&.billing_interval_count || rate.billing_interval_count,
        (override&.billing_interval_unit || rate.billing_interval_unit).to_s]
    end

    def phase_for_cycle(cycle_index)
      cursor = 0

      phases.each do |phase|
        cursor += phase.billing_interval_cycle_count
        return phase if cycle_index < cursor
      end

      nil
    end
  end

  # ---------------------------------------------------------------------------------------
  # Driving the two engines
  # ---------------------------------------------------------------------------------------
  class Runner
    SCENARIO_TIMEOUT = 10

    def initialize(inputs)
      @inputs = inputs
    end

    attr_reader :inputs

    delegate :scenario, to: :inputs

    def run(query)
      old_error = nil
      new_error = nil
      old_windows = nil
      new_windows = nil

      begin
        old_windows = guard { old_for(query) }
      rescue Exception => e # rubocop:disable Lint/RescueException -- Timeout::Error is not a StandardError in every path
        old_error = "#{e.class}: #{e.message}"
      end

      begin
        new_windows = guard { new_for(query) }
      rescue Exception => e # rubocop:disable Lint/RescueException
        new_error = "#{e.class}: #{e.message}"
      end

      [old_windows, new_windows, old_error, new_error]
    end

    def guard(&)
      Timeout.timeout(SCENARIO_TIMEOUT, &)
    end

    # The new engine is a single object per scenario: it is lazy and memoized, and rebuilding it
    # per query would hide the fact that repeated queries share one walk.
    def schedule
      @schedule ||= Billing::Schedule.new(
        anchor_date: inputs.anchor_date,
        timezone: scenario.timezone,
        starts_at: inputs.started_at.utc,
        ends_at: inputs.ends_at,
        terms: Billing::Terms.new(timing: scenario.timing.to_sym, prorated: scenario.prorated),
        rates: Billing::RateTimeline.new(inputs.rates),
        phases: inputs.phases.map do |phase|
          Billing::Schedule::Phase.new(
            position: phase.position, cycle_count: phase.billing_interval_cycle_count,
            code: phase.code, override: phase.rate_override
          )
        end,
        anchor_policy: Billing::AnchorPolicy::Realigning
      )
    end

    def new_for(query)
      case query
      when :segments_overlapping then normalise_new(schedule.segments_overlapping(overlap_range))
      when :segments_due_by then normalise_new(schedule.segments_due_by(due_by_at))
      when :next_billing_at then schedule.next_billing_at(after: inputs.midpoint)
      end
    end

    def old_for(query)
      case query
      when :segments_overlapping
        normalise_old(legacy(range: overlap_range, exclude_out_of_range: false, termination: inputs.terminating?).periods)
      when :segments_due_by
        normalise_old(legacy(range: inputs.walk_begin..due_by_at, exclude_out_of_range: true, termination: false).periods)
      when :next_billing_at
        legacy(range: inputs.walk_begin..inputs.midpoint, exclude_out_of_range: true, termination: false).next_billing_at
      end
    end

    def overlap_range
      inputs.walk_begin..(inputs.ends_at || inputs.walk_end)
    end

    def due_by_at = inputs.walk_end

    def legacy(range:, exclude_out_of_range:, termination:)
      LegacyEngine::BillingPeriods::DatesService.from_subscription_rate_card(
        inputs.subscription_rate_card,
        rates: inputs.rates,
        range:,
        rate_phases: LegacyEngine::SubscriptionRateCards::ResolveRatePhasesService::RatePhases.new(phases: inputs.phases),
        options: LegacyEngine::BillingPeriods::DatesService::Options.new(
          timezone: scenario.timezone,
          exclude_out_of_range:,
          realign_billing_anchor: true,
          termination:
        )
      )
    end

    def normalise_new(segments)
      segments.map do |segment|
        Window.new(
          started_at: segment.started_at.utc,
          ended_at: segment.ended_at.utc,
          cycle_started_at: segment.cycle_started_at.utc,
          cycle_index: segment.cycle_index,
          billing_at: segment.billing_at.utc,
          rate_code: segment.rate.code,
          override_code: segment.rate_override&.code,
          proration_ratio: segment.proration_ratio
        )
      end
    end

    # The ONLY normalisation applied to the old engine: its inclusive `period_to` becomes the
    # exclusive end by adding the smallest representable step. Nothing else is touched — in
    # particular a `period_to` that does not meet the next `period_from` stays visible as a gap.
    def normalise_old(periods)
      periods.map do |period|
        Window.new(
          started_at: period.period_from.utc,
          ended_at: exclusive_end(period.period_to),
          cycle_started_at: period.cycle.period_from.utc,
          cycle_index: period.cycle.index,
          billing_at: exclusive_billing_at(period),
          rate_code: period.rate.code,
          override_code: period.rate_override&.code,
          proration_ratio: period.proration_ratio
        )
      end
    end

    def exclusive_end(period_to)
      Time.zone.at(period_to.utc.to_r + Rational(1, 1_000_000_000)).utc
    end

    # Arrears bills at the close of the window, so the old engine's inclusive close is put on the
    # same footing as the new engine's exclusive one. Advance bills at the open, which needs no
    # conversion.
    def exclusive_billing_at(period)
      billing_at = period.billing_at

      period.rate.rate_card.advance? ? billing_at.utc : exclusive_end(billing_at)
    end
  end

  # ---------------------------------------------------------------------------------------
  # Coherence of the old engine, judged on its own output alone
  # ---------------------------------------------------------------------------------------
  module OldCoherence
    module_function

    # A gap or an overlap between consecutive CYCLES is incoherent; between two slices of the
    # same cycle the old engine cuts at `moment_before`, which is contiguous by construction.
    def breakage(old_windows, inputs, new_windows)
      return {mechanism: "raised", detail: nil} if old_windows.nil?

      cycles = old_windows.group_by(&:cycle_index).transform_values do |group|
        [group.map(&:started_at).min, group.map(&:ended_at).max]
      end.sort_by { |index, _| index }

      overlap = first_overlap(cycles)
      return overlap if overlap

      gap = first_gap(cycles)
      return gap if gap

      if old_windows.empty? && !new_windows.nil? && new_windows.any?
        return {mechanism: "empty walk where cycles plainly exist", detail: "new produced #{new_windows.size} segments"}
      end

      truncation(cycles, inputs, new_windows)
    end

    def first_overlap(cycles)
      cycles.each_cons(2) do |(_, (_, previous_end)), (index, (start, _))|
        if start < previous_end - Rational(1, 1_000)
          return {mechanism: "overlapping cycles", detail: "cycle #{index} opens #{previous_end - start}s before the previous one closes"}
        end
      end
      nil
    end

    def first_gap(cycles)
      cycles.each_cons(2) do |(_, (_, previous_end)), (index, (start, _))|
        gap = start - previous_end
        if gap > 1
          return {mechanism: "gap between cycles", detail: "#{gap.round(6)}s of unbilled time before cycle #{index}"}
        end
      end
      nil
    end

    # The walk stopped early: the old engine emitted materially fewer cycles than the new one
    # over the same span. One cycle of slack absorbs the range-filter differences that are a
    # legitimate disagreement rather than a wedge.
    def truncation(cycles, _inputs, new_windows)
      return nil if new_windows.nil?

      new_cycles = new_windows.map(&:cycle_index).uniq.size
      return nil unless cycles.size + 1 < new_cycles

      {mechanism: "truncated walk", detail: "old produced #{cycles.size} cycles, new produced #{new_cycles}"}
    end
  end

  # ---------------------------------------------------------------------------------------
  # Comparison and classification
  # ---------------------------------------------------------------------------------------
  class Comparison
    def initialize(scenario, inputs, query, old_windows, new_windows, old_error, new_error, runner: nil)
      @scenario = scenario
      @inputs = inputs
      @query = query
      @runner = runner
      @old = old_windows
      @new = new_windows
      @old_error = old_error
      @new_error = new_error
    end

    attr_reader :scenario, :inputs, :query, :old, :new, :old_error, :new_error, :runner

    def outcome
      Outcome.new(scenario:, query:, old:, new:, divergences:, old_error:, new_error:, comparable: true)
    end

    def divergences
      @divergences ||= compute
    end

    def compute
      return [broken("old engine raised", old_error)] if old_error
      return [suspect("new engine raised", "exception", new_error)] if new_error
      return timestamp_divergences if query == :next_billing_at

      breakage = OldCoherence.breakage(old, inputs, new)
      return [broken(breakage[:mechanism], breakage[:detail])] if breakage

      window_divergences
    end

    def broken(mechanism, detail = nil)
      Divergence.new(classification: :OLD_ENGINE_BROKEN, mechanism:, field: nil, detail:)
    end

    def suspect(mechanism, field, detail)
      Divergence.new(classification: :NEW_ENGINE_SUSPECT, mechanism:, field:, detail:)
    end

    def intentional(mechanism, field, detail)
      Divergence.new(classification: :INTENTIONAL, mechanism:, field:, detail:)
    end

    def undecided(mechanism, field, detail)
      Divergence.new(classification: :UNDECIDED, mechanism:, field:, detail:)
    end

    # -- next_billing_at ------------------------------------------------------------------
    def timestamp_divergences
      return [] if old.nil? && new.nil?
      return [broken("nil next_billing_at: the walk kept no cycle (R23 max over kept cycles)", "new=#{fmt(new)}")] if old.nil? && new
      return [suspect("new engine has no next_billing_at", "next_billing_at", "old=#{fmt(old)}")] if new.nil? && old
      return [] if close?(exclusive(old), new)
      return [] if scenario.timing == "advance" && close?(old, new)

      # A scalar read off a broken walk is not evidence about the new engine. The walk that
      # produced the old answer is checked for coherence before the answer is judged at all.
      breakage = old_walk_breakage
      return [broken("#{breakage[:mechanism]} in the walk behind next_billing_at", breakage[:detail])] if breakage

      [classify_next_billing_at]
    end

    # The old engine's arrears next_billing_at is the boundary AFTER the one closing the cycle
    # being billed (R24), while the new engine answers "the next instant anything falls due".
    # The two only coincide when the query instant sits on a due boundary, so a disagreement is
    # the redesign - unless the new answer is not strictly after the query instant, which would
    # be a defect.
    # The walk the old engine's scalar was reduced from (R23: a max over the cycles it kept).
    def old_walk_breakage
      return nil unless runner

      windows = runner.guard { runner.normalise_old(runner.legacy(range: inputs.walk_begin..inputs.midpoint, exclude_out_of_range: true, termination: false).periods) }
      OldCoherence.breakage(windows, inputs, nil)
    rescue Exception # rubocop:disable Lint/RescueException
      {mechanism: "raised", detail: nil}
    end

    def classify_next_billing_at
      detail = "old=#{fmt(old)} new=#{fmt(new)} after=#{fmt(inputs.midpoint)}"

      return suspect("next_billing_at is not after the query instant", "next_billing_at", detail) if new <= inputs.midpoint
      # R23: the old answer is a max over the cycles the walk KEPT, not the next boundary after
      # the range, so a truncated walk answers with an instant already in the past. S3 is exactly
      # this: the scheduler's clock never advances again.
      return broken("next_billing_at at or before the query instant (R23/S3 stall)", detail) if old <= inputs.midpoint
      return broken("next_billing_at built on a UTC-midnight cursor (R26)", detail) if utc_midnight_cursor?(old)
      return intentional("CONTRACT BUGS 1: the end-of-day close moves the arrears due instant", "next_billing_at", detail) if tz_hole_shaped?(old, new)
      # BUGS 3: the old answer is read off the cycle already built, so when the cadence changes
      # at the next boundary it reports a fencepost of the OLD cadence. That lands either side of
      # the truth depending on which cadence is longer, so the test is whether the cadence really
      # does change at the cycle the new engine says falls due - not which answer is larger.
      return intentional("CONTRACT BUGS 3: next_billing_at resolves the NEXT cycle's cadence", "next_billing_at", detail) if cadence_change_at_next_due?
      return intentional("CONTRACT next_billing_at: the next instant anything falls due; the old answer skips whatever its UTC-day-snapped range already counts as billed (R23/R24/R48)", "next_billing_at", detail) if skipped_by_snapped_range?
      return broken("next_billing_at is a max over cycles at different cadences and points past an unbilled due instant (R23/R24)", detail) if points_past_an_unbilled_due_instant?

      undecided("next_billing_at semantics differ", "next_billing_at", detail)
    end

    # The old answer is a max over the cycles its walk KEPT (R23), and membership is decided
    # against a range end snapped to the whole UTC day (R48). So the instant the new engine
    # names is one the old walk has already swallowed into "billing now" — an answer one whole
    # cycle further on, for advance and arrears alike (R24 is the arrears shape of it).
    # R23 reduces the walk with `max`, so when a schedule speeds up - a long cycle followed by
    # short ones - the long cycle's own fencepost outranks every later one and the answer lands
    # past due segments the old walk never billed. A scheduler driven by that clock skips them.
    def points_past_an_unbilled_due_instant?
      old > new && new > old_range_end
    end

    def skipped_by_snapped_range?
      old > new && new <= old_range_end
    end

    def cadence_change_at_next_due?
      walk = runner&.guard { runner.normalise_new(runner.schedule.segments_overlapping(runner.overlap_range)) }
      segment = walk&.find { close?(it.billing_at, new) }
      return false unless segment&.cycle_index&.positive?

      opens = walk.group_by(&:cycle_index).transform_values { it.first.cycle_started_at }
      previous_open = opens[segment.cycle_index - 1]
      return false unless previous_open

      inputs.effective_interval(segment.cycle_index, opens.fetch(segment.cycle_index)) !=
        inputs.effective_interval(segment.cycle_index - 1, previous_open)
    end

    # -- windows --------------------------------------------------------------------------
    #
    # Windows are aligned on their own start instant rather than by position, so that one extra
    # window on one side does not report every later window as a disagreement.
    def window_divergences
      found = []
      old_by_start = old.group_by { it.started_at.to_r }
      new_by_start = new.group_by { it.started_at.to_r }
      old_left = []
      new_left = []

      (old_by_start.keys | new_by_start.keys).sort.each do |start|
        old_group = old_by_start[start] || []
        new_group = new_by_start[start] || []

        if old_group.empty?
          new_left.concat(new_group)
        elsif new_group.empty?
          old_left.concat(old_group)
        elsif old_group.size != new_group.size
          found << suspect("different number of slices opening at the same instant", "count",
            "OLD:\n#{render(old_group)}\nNEW:\n#{render(new_group)}")
        else
          old_group.zip(new_group).each { |o, n| found.concat(compare_window(o, n)) }
        end
      end

      # A window whose START moved is ONE disagreement, not a missing window plus an invented
      # one. Leftovers that close on the same instant are the same window seen twice, so they
      # are paired up and compared field by field like any other pair; whatever is still
      # unpaired really is present on one side only.
      pair_by_close(old_left, new_left) { |o, n| found.concat(compare_window(o, n)) }

      found.concat(old_left.map { classify_old_only(it) })
      found.concat(new_left.map { classify_new_only(it) })
      found
    end

    def pair_by_close(old_left, new_left)
      old_left.dup.each do |old_window|
        match = new_left.find { close?(it.ended_at, old_window.ended_at) }
        next unless match

        old_left.delete(old_window)
        new_left.delete(match)
        yield(old_window, match)
      end
    end

    # A window the old engine emitted and the new one did not.
    def classify_old_only(window)
      detail = "OLD only: #{window}"

      # `moment_before`/`min(period_to, range.end)` can close a slice on the instant it opens.
      # It is still emitted and still bills a whole day (R7), which is why it is breakage rather
      # than a rounding difference.
      return broken("zero-length window that still bills a day (R7/S17)", detail) if close?(window.ended_at, window.started_at)

      return intentional("CONTRACT segments_overlapping: only windows intersecting the range (old snaps range.end to the UTC day, R48)", "count", detail) unless overlaps_query_range?(window)
      return broken("cycle boundary snapped to UTC midnight (R26)", detail) if utc_midnight_cursor?(window.cycle_started_at)

      suspect("old engine emitted a window the new engine did not", "count", detail)
    end

    # A window the new engine emitted and the old one did not.
    def classify_new_only(window)
      detail = "NEW only: #{window}"

      return undecided("an arrears slice cut off by a rate change falls due at the cut, not at the cycle close", "billing_at", detail) if arrears_slice_due_early?(window)
      return intentional("CONTRACT four-method redesign: cycle_due? drops in-range cycles (R45/R46, S7)", "count", detail) if within_old_range?(window)
      return broken("termination walk stopped before the card ended (R26 cursor)", detail) if past_the_end_of_the_old_walk?(window)

      suspect("new engine emitted a window the old engine did not", "count", detail)
    end

    def overlaps_query_range?(window)
      range = query_range
      window.ended_at > range.begin && window.started_at <= range.end
    end

    # R46, replayed exactly. Advance keeps a cycle whose window has OPENED by the range end;
    # arrears only one that has CLOSED by then, where "closed" is `cycle_due_at`, the local day
    # after the cycle's last instant resolved in UTC (R26). So the in-progress cycle is invisible
    # to an arrears walk however `exclude_out_of_range` is set - S7 - while the new engine's
    # `segments_overlapping` asks only whether the window intersects the range and returns it.
    #
    # The test is on the CYCLE, not on the segment: a cycle cut by a rate change is kept or
    # dropped whole.
    def within_old_range?(window)
      return false unless window.started_at <= query_range.end && window.ended_at > query_range.begin

      dropped_by_old_cycle_due?(window)
    end

    def dropped_by_old_cycle_due?(window)
      return window.cycle_started_at > old_range_end if scenario.timing == "advance"

      last_instant = cycle_end_of(window).in_time_zone(scenario.timezone) - 1.second
      last_instant.to_date.next_day.beginning_of_day.utc > old_range_end
    end

    # CONTRACT walk rule 7 makes billing_at a property of the SEGMENT: an arrears slice ending
    # at a rate change falls due at the change, while R37 gives every slice of a cycle the
    # cycle's own instant. Rule 7 states the new behaviour plainly, but the contract's BUGS list
    # - its register of deliberate divergences - does not carry it, so this is raised for a human
    # rather than waved through as intended.
    def arrears_slice_due_early?(window)
      return false unless scenario.timing == "arrears" && query == :segments_due_by

      inputs.rates.any? { close?(it.effective_from, window.ended_at) }
    end

    def cycle_end_of(window)
      new.select { it.cycle_index == window.cycle_index }.map(&:ended_at).max
    end

    # The old engine snaps both ends of its range to whole UTC days, whatever the customer's
    # timezone (R48/R53).
    def old_range_end = @old_range_end ||= query_range.end.to_date.end_of_day.utc

    # In termination mode the old engine keeps every cycle overlapping the range (R46's
    # termination row is a plain overlap test), so it has no legitimate reason to stop before
    # the card's own end. When it does, the tail it left behind is unbilled service time - the
    # R26 cursor landing on UTC midnight and overshooting the snapped range end.
    def past_the_end_of_the_old_walk?(window)
      return false unless inputs.terminating?
      return false if old.empty?

      last_end = old.map(&:ended_at).max
      window.started_at >= last_end - 1 && window.ended_at <= inputs.ends_at + 1 && last_end < inputs.ends_at
    end

    # The range the OLD engine was actually given for this query, which is what its own filters
    # were evaluated against.
    def query_range
      case query
      when :segments_due_by then inputs.walk_begin..inputs.walk_end
      when :next_billing_at then inputs.walk_begin..inputs.midpoint
      else inputs.walk_begin..(inputs.ends_at || inputs.walk_end)
      end
    end

    def compare_window(old_window, new_window)
      found = []
      where = "OLD #{old_window}\n  NEW #{new_window}"
      windows_match = close?(old_window.ended_at, new_window.ended_at)

      found << classify_started_at(old_window, new_window, where) unless close?(old_window.started_at, new_window.started_at)
      found << classify_ended_at(old_window, new_window, where) unless windows_match

      # Once the window itself is established as breakage, everything measured against it - when
      # it falls due, what share of a cycle it is - is that same defect reported again. Listing
      # each consequence separately would inflate the count and bury the mechanism.
      return found.compact if found.any? { it.classification == :OLD_ENGINE_BROKEN }

      found << classify_billing_at(old_window, new_window, where) unless close?(old_window.billing_at, new_window.billing_at)

      if old_window.cycle_started_at != new_window.cycle_started_at
        found << classify_cycle_started_at(old_window, new_window, where)
      end

      found << suspect("rate disagrees", "rate", where) if old_window.rate_code != new_window.rate_code
      found << suspect("rate_override in force disagrees", "rate_override", where) if old_window.override_code != new_window.override_code

      unless ratio_close?(old_window.proration_ratio, new_window.proration_ratio)
        found << classify_ratio(old_window, new_window, where, windows_match)
      end

      found.compact
    end

    def classify_started_at(old_window, new_window, where)
      return broken("cycle opened on a UTC-midnight cursor (R26)", where) if utc_midnight_cursor?(old_window.started_at)
      return intentional("CONTRACT BUGS 1: the tz-shifted close moves the next window's open", "started_at", where) if tz_hole_shaped?(old_window.started_at, new_window.started_at)

      suspect("started_at disagrees", "started_at", where)
    end

    def classify_ended_at(old_window, new_window, where)
      return intentional("CONTRACT BUGS 1: (boundary - 1s).end_of_day leaves a tz-sized hole", "ended_at", where) if tz_hole_shaped?(old_window.ended_at, new_window.ended_at)
      return broken("cycle end snapped to a UTC day (R26/R48)", where) if utc_midnight_cursor?(old_window.ended_at)

      suspect("ended_at disagrees", "ended_at", where)
    end

    def classify_billing_at(old_window, new_window, where)
      return intentional("CONTRACT BUGS 1: the tz-shifted close moves the arrears due instant", "billing_at", where) if tz_hole_shaped?(old_window.billing_at, new_window.billing_at)

      suspect("billing_at disagrees", "billing_at", where)
    end

    def classify_cycle_started_at(old_window, new_window, where)
      return broken("cycle opened on a UTC-midnight cursor (R26)", where) if utc_midnight_cursor?(old_window.cycle_started_at)

      suspect("cycle_started_at disagrees", "cycle_started_at", where)
    end

    def classify_ratio(old_window, new_window, where, windows_match)
      old_ratio = old_window.proration_ratio
      new_ratio = new_window.proration_ratio
      detail = "#{where}\n  old=#{old_ratio} new=#{new_ratio} (#{new_ratio.to_f})"

      return intentional("CONTRACT BUGS 4: Float vs Rational", "proration_ratio", detail) if ratio_close?(old_ratio, new_ratio, 1e-6)
      return suspect("proration_ratio disagrees on windows that also disagree", "proration_ratio", detail) unless windows_match
      return intentional("CONTRACT BUGS 2: ceil'd billed_days over a date-subtracted full period (R7/R42, S4)", "proration_ratio", detail) if ceil_rule_shaped?(old_ratio, new_ratio)

      suspect("proration_ratio disagrees", "proration_ratio", detail)
    end

    # The old rule over-counts WHOLE DAYS: old = ceil_days/F, new = covered_days/F for the same
    # F, so their difference is d/F for a small integer d. Solving F = d/(old - new) and checking
    # that both ratios are then whole numbers of days out of F identifies the mechanism exactly,
    # rather than inferring it from the size of the difference.
    def ceil_rule_shaped?(old_ratio, new_ratio)
      delta = old_ratio.to_f - new_ratio.to_f
      return false unless delta > 0

      (1..3).any? do |over_counted_days|
        full = over_counted_days / delta
        next false unless whole?(full) && full.round.positive?

        days = full.round
        whole?(new_ratio.to_f * days) && whole?(old_ratio.to_f * days)
      end
    end

    def whole?(value) = (value - value.round).abs < 1e-6

    # The old engine's close is `(boundary - 1s).end_of_day.utc`. Rebuilding that formula from
    # the NEW engine's answer and landing on the OLD engine's answer names the mechanism exactly
    # instead of inferring it from the size of the difference.
    def tz_hole_shaped?(old_time, new_time)
      return false if old_time.nil? || new_time.nil?

      close?(exclusive((new_time.utc - 1.second).end_of_day.utc), old_time)
    end

    # R26: `period_to.in_time_zone(tz).to_date.next_day.beginning_of_day` resolves in Time.zone
    # (UTC), so the arrears and termination cursor lands on UTC midnight instead of the
    # customer's. Diagnostic: the instant IS UTC midnight in a zone whose boundaries are not.
    def utc_midnight_cursor?(time)
      return false if time.nil? || scenario.timezone == "UTC"

      time.utc == time.utc.beginning_of_day
    end

    def exclusive(time) = Time.zone.at(time.to_r + Rational(1, 1_000_000_000)).utc

    def close?(a, b)
      return a == b if a.nil? || b.nil?

      (a.to_r - b.to_r).abs <= END_TOLERANCE
    end

    def ratio_close?(a, b, tolerance = RATIO_TOLERANCE)
      (a.to_f - b.to_f).abs <= tolerance
    end

    def fmt(time) = time&.utc&.strftime("%Y-%m-%d %H:%M:%S.%6N")

    def render(windows) = windows.map { "    #{it}" }.join("\n")
  end

  # ---------------------------------------------------------------------------------------
  # Invariants asserted on the NEW engine alone
  # ---------------------------------------------------------------------------------------
  class Invariants
    Violation = Data.define(:rule, :detail)

    def initialize(scenario, inputs, runner)
      @scenario = scenario
      @inputs = inputs
      @runner = runner
    end

    attr_reader :scenario, :inputs, :runner

    def violations
      segments = Timeout.timeout(Runner::SCENARIO_TIMEOUT) { runner.schedule.segments_overlapping(runner.overlap_range) }

      [
        *contiguity(segments),
        *ratio_bounds(segments),
        *cycle_ratio_sums(segments),
        *billing_order(segments),
        *cycle_start_order(segments),
        *next_billing_at_strictly_after,
        *due_by_agrees_with_the_walk(segments),
        *next_billing_at_agrees_with_the_walk(segments),
        *queries_are_repeatable
      ]
    rescue Timeout::Error
      [Violation.new(rule: "the walk terminates", detail: "segments_overlapping did not terminate")]
    end

    def contiguity(segments)
      earliest_rate = inputs.rates.map(&:effective_from).min

      segments.each_cons(2).filter_map do |current, following|
        next if current.ended_at == following.started_at
        # A stretch with no rate in force emits nothing, which is a hole in the OUTPUT rather
        # than in the schedule; it can only sit before the first rate ever takes effect.
        next if following.started_at <= earliest_rate

        Violation.new(
          rule: "segments are contiguous and non-overlapping",
          detail: "#{current.ended_at.utc} -> #{following.started_at.utc} " \
                  "(#{(following.started_at - current.ended_at).round(6)}s)"
        )
      end
    end

    def ratio_bounds(segments)
      segments.filter_map do |segment|
        next if segment.proration_ratio.between?(0, 1)

        Violation.new(rule: "proration_ratio in [0, 1]", detail: "#{segment.proration_ratio} on #{segment.started_at.utc}")
      end
    end

    # Two statements, not one. `sum <= 1` holds for every cycle: a cycle clipped by the cursor,
    # by `ends_at`, or opened mid-window by a cadence change under Fixed legitimately bills less
    # than a whole cycle. `sum == 1` is asserted only where nothing can clip: an interior cycle,
    # covered end to end, on a schedule whose cadence never changes. That is exactly the shape
    # the 103% bug lived in, so the assertion still has teeth.
    def cycle_ratio_sums(segments)
      return [] unless scenario.prorated

      by_cycle = segments.group_by(&:cycle_index)
      sums = by_cycle.transform_values { |group| group.sum(&:proration_ratio) }

      over = sums.filter_map do |index, sum|
        next if sum <= 1

        Violation.new(rule: "the segments of a cycle never sum above 1", detail: "cycle #{index} sums to #{sum} (#{sum.to_f})")
      end

      return over unless steady_cadence?

      interior = by_cycle.keys.sort[1..-2] || []
      over + interior.filter_map do |index|
        group = by_cycle.fetch(index)
        next unless group.first.started_at == group.first.cycle_started_at
        next unless by_cycle.key?(index + 1)
        next unless group.last.ended_at == by_cycle.fetch(index + 1).first.cycle_started_at

        sum = sums.fetch(index)
        next if sum == 1

        Violation.new(rule: "the segments of a full cycle sum to exactly 1", detail: "cycle #{index} sums to #{sum} (#{sum.to_f})")
      end
    end

    # A cadence change reshapes the cycle the change lands in, and `ends_at` cuts the last one.
    def steady_cadence?
      scenario.rate_plan != :cadence_change && scenario.phase_plan == :none && scenario.ends_kind == :none
    end

    def billing_order(segments)
      segments.filter_map do |segment|
        ok = segment.billing_at >= if scenario.timing == "advance"
               segment.started_at
             else
               segment.ended_at
             end
        next if ok

        Violation.new(
          rule: "billing_at is at or after the segment's own boundary",
          detail: "#{scenario.timing}: billing_at=#{segment.billing_at.utc} started_at=#{segment.started_at.utc} ended_at=#{segment.ended_at.utc}"
        )
      end
    end

    def cycle_start_order(segments)
      segments.filter_map do |segment|
        next if segment.cycle_started_at <= segment.started_at

        Violation.new(rule: "cycle_started_at is at or before started_at", detail: segment.to_s)
      end
    end

    # The three queries read the same walk, and the walk is lazy and memoized (CONTRACT rule 9).
    # A query that walks too little answers with a truncated list; one that re-walks can answer
    # differently the second time. These three catch both without needing the old engine.
    def probes
      span = inputs.walk_end.to_r - inputs.cursor_origin.to_r
      (0..8).map { Time.zone.at(inputs.cursor_origin.to_r + (span * it / 8)).utc }
    end

    def due_by_agrees_with_the_walk(segments)
      probes.filter_map do |probe|
        due = runner.schedule.segments_due_by(probe)
        expected = segments.select { it.billing_at <= probe }
        next if due.map(&:started_at) == expected.map(&:started_at)

        Violation.new(
          rule: "segments_due_by(t) is exactly the segments billing at or before t",
          detail: "t=#{probe} due=#{due.size} expected=#{expected.size}"
        )
      end
    end

    def next_billing_at_agrees_with_the_walk(segments)
      probes.filter_map do |probe|
        answer = runner.schedule.next_billing_at(after: probe)
        expected = segments.map(&:billing_at).select { it > probe }.min
        next if answer == expected || (expected.nil? && !answer.nil?)

        Violation.new(
          rule: "next_billing_at(after: t) is the earliest billing_at strictly after t",
          detail: "t=#{probe} answer=#{answer.inspect} expected=#{expected.inspect}"
        )
      end
    end

    def queries_are_repeatable
      first = runner.schedule.segments_overlapping(runner.overlap_range).map(&:started_at)
      second = runner.schedule.segments_overlapping(runner.overlap_range).map(&:started_at)
      return [] if first == second

      [Violation.new(rule: "repeated queries return the same answer", detail: "#{first.size} then #{second.size}")]
    end

    def next_billing_at_strictly_after
      probes = [inputs.walk_begin, inputs.midpoint, inputs.walk_end]

      probes.filter_map do |probe|
        answer = Timeout.timeout(Runner::SCENARIO_TIMEOUT) { runner.schedule.next_billing_at(after: probe) }
        next if answer.nil? || answer > probe

        Violation.new(rule: "next_billing_at(after:) is strictly after the query instant or nil", detail: "after=#{probe.utc} answer=#{answer.utc}")
      rescue Timeout::Error
        Violation.new(rule: "the walk terminates", detail: "next_billing_at(after: #{probe.utc}) did not terminate")
      end
    end
  end

  # ---------------------------------------------------------------------------------------
  # The space
  # ---------------------------------------------------------------------------------------
  module Space
    SEED = 20260904

    CORE = {
      timing: TIMINGS,
      cadence: [[1, "day"], [1, "week"], [1, "month"], [1, "year"]],
      anchor_kind: %i[equal day31],
      start_tod: %i[midnight mid_morning],
      rate_plan: %i[none midday_change],
      phase_plan: %i[none one_bounded],
      timezone: ["UTC", "America/New_York", "Asia/Tokyo"],
      ends_kind: %i[none mid_cycle],
      span: [:normal],
      prorated: [true]
    }.freeze

    FULL = {
      timing: TIMINGS,
      cadence: CADENCES,
      anchor_kind: ANCHOR_KINDS,
      start_tod: START_TIMES_OF_DAY,
      rate_plan: RATE_PLANS,
      phase_plan: PHASE_PLANS,
      timezone: TIMEZONES,
      ends_kind: ENDS_KINDS,
      span: SPANS,
      prorated: [true, false]
    }.freeze

    module_function

    def core
      keys = CORE.keys
      CORE.values.first.product(*CORE.values[1..]).each_with_index.map do |values, index|
        Scenario.new(id: "core-#{index}", **keys.zip(values).to_h)
      end
    end

    def sampled(count, seed: SEED)
      random = Random.new(seed)

      Array.new(count) do |index|
        Scenario.new(id: "rand-#{index}", **FULL.transform_values { |values| values[random.rand(values.size)] })
      end
    end

    # Every DST transition in the matrix, walked daily and weekly in both hemispheres, so a
    # sampled run cannot miss them.
    def dst
      zones = ["America/New_York", "Europe/Paris", "Pacific/Auckland"]
      spans = %i[spring_forward_north fall_back_north spring_forward_south fall_back_south]

      index = -1
      TIMINGS.product([[1, "day"], [1, "week"], [1, "month"]], zones, spans).map do |timing, cadence, timezone, span|
        index += 1
        Scenario.new(
          id: "dst-#{index}", timing:, cadence:, anchor_kind: :equal, start_tod: :midnight,
          rate_plan: :midday_change, phase_plan: :none, timezone:, ends_kind: :none, span:, prorated: true
        )
      end
    end
  end

  # ---------------------------------------------------------------------------------------
  # Driving the whole space
  # ---------------------------------------------------------------------------------------
  Report = Data.define(:outcomes, :invariant_violations, :scenario_count) do
    def divergences = outcomes.flat_map(&:divergences)

    def by_classification = divergences.group_by(&:classification).transform_values(&:size)

    def suspects = outcomes.select { |o| o.divergences.any? { it.classification == :NEW_ENGINE_SUSPECT } }

    def undecided = outcomes.select { |o| o.divergences.any? { it.classification == :UNDECIDED } }
  end

  extend ActiveSupport::Testing::TimeHelpers

  # One report per sample size, computed once however many questions are asked of it.
  REPORTS = Concurrent::Map.new

  module_function

  # The old engine's Period#billing_at is `max(boundary, Time.current)` (R38), so a real clock
  # would report every historical window as billing "now" and drown the comparison. Freezing far
  # in the past of every scenario makes that clamp a no-op and billing_at directly comparable.
  # One walk of the space serves every example: the space is a pure function of its seed, so
  # recomputing it per example would multiply a five-second run by the number of questions asked
  # of it.
  def report(sample_size)
    REPORTS.fetch_or_store(sample_size) { run(Space.core + Space.dst + Space.sampled(sample_size)) }
  end

  def run(scenarios)
    outcomes = []
    violations = []

    travel_to(FROZEN_NOW) do
      scenarios.each do |scenario|
        inputs = Inputs.new(scenario)
        runner = Runner.new(inputs)

        QUERIES.each do |query|
          # `ends_at` reaches the old engine only through its termination service, which
          # `segments_overlapping` is the documented replacement for; the other two queries have
          # no old-engine equivalent that knows the card ends.
          next if inputs.terminating? && query != :segments_overlapping

          old_windows, new_windows, old_error, new_error = runner.run(query)
          comparison = Comparison.new(scenario, inputs, query, old_windows, new_windows, old_error, new_error, runner:)
          outcome = comparison.outcome
          outcomes << outcome if outcome.divergences.any?
        end

        Invariants.new(scenario, inputs, runner).violations.each { violations << [scenario, it] }
      rescue Exception => e # rubocop:disable Lint/RescueException
        violations << [scenario, Invariants::Violation.new(rule: "the harness completes", detail: "#{e.class}: #{e.message}")]
      end
    end

    Report.new(outcomes:, invariant_violations: violations, scenario_count: scenarios.size)
  end
end
