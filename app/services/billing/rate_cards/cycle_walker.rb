# frozen_string_literal: true

module Billing
  module RateCards
    class CycleWalker
      attr_reader :current_cycle

      def initialize(rates:, phases:, starts_at:, anchor_date:, timezone:, ends_at: nil)
        @rates = rates.sort_by(&:effective_from)
        @phases = phases
        @starts_at = starts_at.in_time_zone(timezone).beginning_of_day
        @ends_at = ends_at
        @anchor_date = anchor_date
        @timezone = timezone

        validate!(raw_starts_at: starts_at)
      end

      def start
        @current_cycle = build_cycle(index: 0, started_at: starts_at)
      end

      def advance
        return nil unless current_cycle

        @current_cycle = build_cycle(
          index: current_cycle.index + 1,
          started_at: current_cycle.ended_at,
          previous_calendar: current_cycle.calendar
        )
      end

      def resume(timestamp)
        start
        return current_cycle if timestamp.nil?

        @current_cycle = nil if ends_at && timestamp >= ends_at

        while current_cycle && current_cycle.ended_at <= timestamp
          steps = steps_to_advance(timestamp)
          calendar = current_cycle.calendar

          @current_cycle = build_cycle(
            index: current_cycle.index + steps,
            started_at: calendar.boundary_after(current_cycle.started_at, steps),
            previous_calendar: calendar
          )
        end

        current_cycle
      end

      # Include the cycle containing timestamp; nil starts from the beginning.
      def walk_to(timestamp, from: nil)
        cycles = []
        resume(from)

        while current_cycle && current_cycle.started_at <= timestamp
          cycles << current_cycle
          break if current_cycle.ended_at > timestamp

          advance
        end

        cycles
      end

      private

      attr_reader :rates, :phases, :starts_at, :ends_at, :anchor_date, :timezone

      def validate!(raw_starts_at:)
        raise ArgumentError, "at least one rate is required to determine the billing interval" if rates.empty?
        raise ArgumentError, "ends_at #{ends_at} precedes starts_at #{raw_starts_at}" if ends_at && ends_at < raw_starts_at
        raise ArgumentError, "at least one phase is required" if phases.empty?
        raise ArgumentError, "the last phase must run to the end of the card" unless phases.last.unbounded?
        raise ArgumentError, "only the last phase may run to the end of the card" if phases[0...-1].any?(&:unbounded?)

        rates.each { |rate| Interval.from(rate) }
        phases.each do |phase|
          if phase.rate_override
            # The base rate supplies any interval fields the override leaves unchanged.
            Interval.from(rates.first, override: phase.rate_override)
          end
        end
      end

      # Example with current_cycle.index = 3, using the current calendar:
      # - steps_to_timestamp = 6: the requested time falls in cycle 9.
      # - phase_start_index = 4: the next phase starts at cycle 4.
      # - steps_to_phase_change = 4 - 3 = 1.
      # - steps_to_rate_change = 3: the first boundary at/after the next rate is cycle 6.
      # [6, 1, 3].min = 1: advance from index 3 to 4, apply the new phase, then
      # recalculate the steps to the requested time using the resulting calendar.
      # An unbounded phase or no later rate gives nil, which compact removes.
      def steps_to_advance(timestamp)
        calendar = current_cycle.calendar
        started_at = current_cycle.started_at
        steps_to_timestamp = calendar.intervals_between(started_at, timestamp)

        phase_start_index = next_phase_start_index
        steps_to_phase_change = if phase_start_index
          phase_start_index - current_cycle.index
        end

        next_rate = rates.find { |rate| rate.effective_from > started_at }
        steps_to_rate_change = if next_rate
          boundary = calendar.boundary_at_or_after(next_rate.effective_from)
          calendar.intervals_between(started_at, boundary)
        end

        # Each limit is a number of steps from current_cycle.index.
        [steps_to_timestamp, steps_to_phase_change, steps_to_rate_change].compact.min
      end

      def next_phase_start_index
        phase_boundary_index = 0

        phases.each do |phase|
          return nil if phase.unbounded?

          phase_boundary_index += phase.billing_interval_cycle_count
          if phase_boundary_index > current_cycle.index
            return phase_boundary_index
          end
        end

        raise ArgumentError, "phases must end with an unbounded phase"
      end

      def build_cycle(index:, started_at:, previous_calendar: nil)
        return nil if ends_at && started_at >= ends_at

        phase = phase_by_index(index)
        rate = rate_for_cycle(started_at)
        interval = Interval.from(rate, override: phase.rate_override)

        calendar = if previous_calendar && interval == previous_calendar.interval
          previous_calendar
        else
          anchor = previous_calendar ? started_at.in_time_zone(timezone).to_date : anchor_date
          # Keep calculated boundaries when another resume or walk uses this calendar.
          @calendars ||= {}
          @calendars[[anchor, interval]] ||= Calendar.new(anchor_date: anchor, interval:, timezone:)
        end

        window = calendar.interval_containing(started_at)

        Cycle.new(
          index:,
          started_at:,
          ended_at: ends_at ? [window.end, ends_at].min : window.end,
          phase:,
          calendar:
        )
      end

      def phase_by_index(index)
        phases.each do |phase|
          return phase if phase.unbounded? || index < phase.billing_interval_cycle_count

          index -= phase.billing_interval_cycle_count
        end

        raise ArgumentError, "phases must end with an unbounded phase"
      end

      def rate_for_cycle(timestamp)
        # Before the first rate takes effect, use its interval to build the cycle.
        # This does not price the period before its effective date.
        rates.rfind { |candidate| candidate.effective_from <= timestamp } || rates.first
      end
    end
  end
end
