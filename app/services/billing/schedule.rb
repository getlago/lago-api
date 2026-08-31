# frozen_string_literal: true

module Billing
  # The billing cycles of one rate card, walked forward from its start.
  #
  # A cycle is a period of the calendar clamped by the card's own life: the first starts
  # when the card does rather than on the boundary before it, and the last stops at
  # `ends_at`. Termination is therefore not a mode — it is a schedule with an end, and the
  # same walk produces its final cycle.
  #
  # A rate phase can change the cadence for a run of cycles, so the walk crosses several
  # calendars. A phase that follows another re-anchors on the day it begins, so its cycles
  # are whole rather than clamped to the outgoing calendar (LAGO-1766, reading B).
  #
  # Cycles are what phases count. What a cycle is billed as — one fee, or several when a
  # rate changes inside it — is Billing::Segments, applied per cycle by the caller.
  class Schedule
    TIMINGS = %i[advance arrears].freeze

    # A run of cycles billed on one cadence. `cycle_count` is nil for the last phase, which runs
    # until the schedule ends. `interval` is already resolved: a phase overriding the card's
    # cadence carries the override, one that doesn't carries the card's own. `code` and
    # `override` are carried for the caller: a cycle knows which phase priced it.
    Phase = Data.define(:cycle_count, :interval, :code, :override)

    # One billing cycle. `due_at` is the instant it becomes billable, which is the only
    # thing billing timing changes: the start of the cycle in advance, its end in arrears.
    # `calendar` is the ruler it was measured on, so a caller can ask what share of a whole
    # period any window inside it covers.
    Cycle = Data.define(:index, :from, :to, :due_at, :phase, :calendar)

    def initialize(anchor_date:, phases:, timezone:, starts_at:, timing:, ends_at: nil)
      @anchor_date = anchor_date
      @phases = phases
      @timezone = timezone
      @starts_at = starts_at
      @ends_at = ends_at
      @timing = timing.to_sym

      validate!
    end

    # Every cycle billable by `instant` — the ones whose due_at has arrived. A cycle
    # running over that instant but closing after it is not due yet, so it is left out.
    # @example starting Jan 15, monthly on the 1st: [Jan 15, Feb 1), [Feb 1, Mar 1), ...
    def cycles_due_by(instant)
      walk(instant).first
    end

    # Every cycle due by the end of `range` whose service period reaches into it. Billing a
    # chosen window asks this rather than #cycles_due_by: the window was picked on purpose,
    # so a cycle that closed before it is not wanted even though it is due.
    def cycles_overlapping(range)
      cycles_due_by(range.end).select { |cycle| cycle.to > range.begin }
    end

    # When the first cycle beyond `instant` falls due — the card's own next billing date.
    # Nil once the schedule has ended.
    def next_due_at(instant)
      walk(instant).last&.due_at
    end

    private

    attr_reader :anchor_date, :phases, :timezone, :starts_at, :ends_at, :timing

    # Walks the phases in order, collecting cycles until one falls due after `instant` or
    # the schedule ends. Returns the collected cycles and the first one left out.
    def walk(instant)
      cursor = starts_at
      index = 0
      due = []
      pending = nil

      phases.each_with_index do |phase, position|
        break if pending || ended?(cursor)

        calendar = calendar_for(phase, position, cursor)
        produced = 0

        while phase.cycle_count.nil? || produced < phase.cycle_count
          break if ended?(cursor)

          period = calendar.period_at(cursor)
          cycle = cycle_for(period, cursor, index, phase, calendar)
          if cycle.due_at > instant
            pending = cycle
            break
          end

          due << cycle
          cursor = period.end
          index += 1
          produced += 1
        end
      end

      [due, pending]
    end

    def ended?(cursor)
      ends_at.present? && cursor >= ends_at
    end

    # The card's own anchor opens the schedule; every later phase re-anchors where it
    # begins, so the billing day follows the phase rather than the original calendar.
    def calendar_for(phase, position, cursor)
      anchor = position.zero? ? anchor_date : cursor.in_time_zone(timezone).to_date

      Calendar.new(anchor_date: anchor, interval: phase.interval, timezone:)
    end

    # Clamped by where the walk stands and by the card's end — never by the instant the
    # caller asked about. A cycle in force at that instant still runs to its own boundary.
    def cycle_for(period, cursor, index, phase, calendar)
      from = [period.begin, cursor].max
      to = ends_at ? [period.end, ends_at].min : period.end

      Cycle.new(index:, from:, to:, due_at: (timing == :advance) ? from : to, phase:, calendar:)
    end

    def validate!
      raise ArgumentError, "Unknown billing timing: #{timing.inspect}" unless TIMINGS.include?(timing)
      raise ArgumentError, "ends_at #{ends_at} precedes starts_at #{starts_at}" if ends_at && ends_at < starts_at
      raise ArgumentError, "at least one phase is required" if phases.empty?

      # The last phase must be open and every other one bounded. A bounded last phase would
      # stop producing cycles while the card is still live, which downstream reads as
      # nothing being due rather than as an error.
      raise ArgumentError, "the last phase must run to the end of the schedule" if phases.last.cycle_count
      raise ArgumentError, "only the last phase may run to the end" if phases[..-2].any? { |phase| phase.cycle_count.nil? }
    end
  end
end
