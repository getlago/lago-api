# frozen_string_literal: true

module Billing
  module RateCards
    class Schedule
      TIMINGS = %i[advance arrears].freeze

      Phase = Data.define(:position, :cycle_count, :code, :override) do
        # The card on its own cadence, unbounded and unpriced by any override. It has no
        # position because nothing persisted it — being last is what defines it.
        def self.default = new(position: nil, cycle_count: nil, code: nil, override: nil)
      end

      # What the card charges for a window: which end of it falls due, and whether a partial
      # one is prorated. Constant for the whole schedule.
      Terms = Data.define(:timing, :prorated) do
        def billing_at(window) = (timing == :advance) ? window.started_at : window.ended_at

        def share_of(calendar, window)
          prorated ? calendar.proration_ratio(window.started_at, window.ended_at) : 1.0
        end
      end

      # `ended_at` is exclusive, matching Segment and not the column of the same name.
      Cycle = Data.define(:index, :started_at, :ended_at, :phase, :calendar, :terms) do
        private :calendar, :terms

        def due_at = terms.billing_at(self)

        delegate :billing_at, to: :terms

        def segments(rates:) = Segments.within(started_at...ended_at, rates:)

        def proration_ratio(segment) = terms.share_of(calendar, segment)
      end

      def initialize(anchor_date:, phases:, rates:, prorated:, timezone:, starts_at:, timing:,
        ends_at: nil, realign_billing_anchor: true)
        @anchor_date = anchor_date
        @phases = ordered(phases)
        @rates = rates
        @realign_billing_anchor = realign_billing_anchor
        @timezone = timezone
        @starts_at = starts_at.in_time_zone(timezone).beginning_of_day
        @ends_at = ends_at
        @timing = timing.to_sym

        validate!

        @terms = Terms.new(timing: @timing, prorated:)
      end

      def cycles_due_by(timestamp)
        due, _pending = walk(timestamp)
        due
      end

      def cycles_overlapping(range)
        cycles_due_by(range.end).select { |cycle| cycle.ended_at > range.begin && cycle.started_at < range.end }
      end

      def due_after(timestamp)
        _due, pending = walk(timestamp)
        pending&.due_at
      end

      def next_billing_at(timestamp)
        due, pending = walk(timestamp)

        due.find { |cycle| cycle.ended_at > timestamp }&.due_at || pending&.due_at
      end

      private

      attr_reader :anchor_date, :phases, :rates, :terms, :realign_billing_anchor, :timezone, :starts_at, :ends_at, :timing

      # Both consumers of this engine read the walk twice — /cycles serializes the windows
      # and reports the next billing instant, /bill writes the rows and advances the clock.
      # The previous engine memoized its own walk for the same reason.
      def walk(timestamp)
        @walks ||= {}
        @walks[timestamp] ||= walk_from(timestamp)
      end

      def walk_from(timestamp)
        cursor = starts_at
        index = 0
        due = []
        pending = nil

        anchor = anchor_date
        cadence = nil

        phases.each do |phase|
          break if pending || ended?(cursor)

          produced = 0

          while phase.cycle_count.nil? || produced < phase.cycle_count
            break if ended?(cursor)

            rate = cadence_rate_at(cursor)
            break unless rate

            interval = Interval.from(rate, override: phase.override)
            anchor = cursor.in_time_zone(timezone).to_date if realign_billing_anchor && cadence && cadence != interval
            cadence = interval

            calendar = calendar_for(anchor, interval)
            window = calendar.interval_containing(cursor)
            cycle = cycle_for(window, cursor, index, phase, calendar)
            if cycle.due_at > timestamp
              pending = cycle
              break
            end

            due << cycle
            cursor = window.end
            index += 1
            produced += 1
          end
        end

        [due, pending]
      end

      # The billing order is the phases' own, not the caller's. Sorting here rather than
      # trusting the list means a phase cannot be billed out of sequence by whoever built
      # it; an unpositioned phase is the synthesized default and belongs last. sort_by is
      # not stable, so the given order breaks ties.
      def ordered(phases)
        phases.each_with_index
          .sort_by { |phase, index| [phase.position || Float::INFINITY, index] }
          .map(&:first)
      end

      # One ruler per (anchor, interval) rather than one per cycle: a card that never changes
      # cadence builds a single Calendar however many cycles it walks.
      def calendar_for(anchor, interval)
        @calendars ||= {}
        @calendars[[anchor, interval]] ||= Calendar.new(anchor_date: anchor, interval:, timezone:)
      end

      def cadence_rate_at(cursor)
        Segments.rate_at(rates, cursor) || rates.min_by(&:effective_from)
      end

      def ended?(cursor)
        ends_at.present? && cursor >= ends_at
      end

      def cycle_for(window, cursor, index, phase, calendar)
        started_at = [window.begin, cursor].max
        ended_at = ends_at ? [window.end, ends_at].min : window.end

        Cycle.new(index:, started_at:, ended_at:, phase:, calendar:, terms:)
      end

      def validate!
        raise ArgumentError, "Unknown billing timing: #{timing.inspect}" unless TIMINGS.include?(timing)
        raise ArgumentError, "ends_at #{ends_at} precedes starts_at #{starts_at}" if ends_at && ends_at < starts_at
        raise ArgumentError, "at least one phase is required" if phases.empty?
        raise ArgumentError, "the last phase must run to the end of the schedule" if phases.last.cycle_count
        raise ArgumentError, "only the last phase may run to the end" if phases[..-2].any? { |phase| phase.cycle_count.nil? }
      end
    end
  end
end
