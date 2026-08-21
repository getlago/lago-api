# frozen_string_literal: true

module BillingPeriods
  module Dates
    class BaseService < ::BaseService
      Result = BaseResult[:next_billing_at, :periods]

      def initialize(
        billing_anchor_date:,
        started_at:, rates:, range:,
        subscription_rate_card:,
        options: BillingPeriods::DatesService::Options.default,
        rate_phases: SubscriptionRateCards::ResolveRatePhasesService::RatePhases.new(phases: [])
      )
        @billing_anchor_date = billing_anchor_date
        @options = options
        @started_at = started_at
        @subscription_rate_card = subscription_rate_card
        @rates = rates
        @rate_phases = rate_phases
        @range = range
        super
      end

      def call
        periods, next_billing_at = periods_and_next_billing_at
        result.periods = periods
        result.next_billing_at = next_billing_at
        result
      end

      private

      attr_reader :billing_anchor_date, :options, :started_at, :subscription_rate_card, :rates, :rate_phases, :range

      delegate :timezone, :exclude_out_of_range, :realign_billing_anchor, to: :options

      def periods_and_next_billing_at
        periods = cycles.flat_map { |cycle| periods_for_cycle(cycle) }
        next_billing_at = cycles.map(&:next_billing_at).max

        [periods, next_billing_at]
      end

      def cycles
        @cycles ||= begin
          built_cycles = []
          cycle_start = started_at.utc
          cycle_index = 0
          anchor_date = billing_anchor_date
          previous_interval = nil

          if sorted_rates.any?
            loop do
              interval = interval_for_cycle(cycle_start, cycle_index)
              break unless interval

              if realign_billing_anchor && previous_interval && previous_interval != interval_key(interval)
                anchor_date = cycle_start.in_time_zone(timezone).to_date
              end

              cycle = cycle_at(cycle_start, cycle_index, interval:, anchor_date:)
              break unless cycle
              break if cycle.period_from > range_end && cycle_due_after_range?(cycle)

              built_cycles << cycle if cycle_due?(cycle)

              next_cycle_start = next_cycle_start_for(cycle)
              break if next_cycle_start <= cycle_start

              cycle_start = next_cycle_start
              cycle_index += 1
              previous_interval = interval_key(interval)
            end
          end

          built_cycles
        end
      end

      def cycle_at(cycle_start, cycle_index, interval:, anchor_date:)
        rate_phase, count, unit = interval
        boundaries = boundaries_for(count, unit, anchor_date:)
        boundary_index = boundaries.index_on_or_before(cycle_start.in_time_zone(timezone))
        period_from = [boundaries.at(boundary_index).utc, cycle_start].max
        period_to = (boundaries.at(boundary_index + 1) - 1.second).end_of_day.utc

        BillingPeriods::DatesService::Cycle.new(
          index: cycle_index,
          period_from:,
          period_to:,
          next_billing_at: next_billing_at_for(boundaries, boundary_index),
          rate_phase:
        ).tap { |cycle| boundaries_by_cycle[cycle] = boundaries }
      end

      def interval_for_cycle(cycle_start, cycle_index)
        interval_source = interval_source_for(cycle_start)
        return unless interval_source

        rate_phase = rate_phase_for_cycle(cycle_index)
        count = rate_phase&.rate_override&.billing_interval_count || interval_source.billing_interval_count
        unit = rate_phase&.rate_override&.billing_interval_unit || interval_source.billing_interval_unit

        [rate_phase, count, unit]
      end

      def interval_key(interval)
        _rate_phase, count, unit = interval
        [count, unit]
      end

      def periods_for_cycle(cycle)
        segment_start, segment_end = segment_range_for(cycle)
        return [] if segment_start > segment_end

        segment_starts = [segment_start]
        segment_starts.concat(
          sorted_rates
            .select { |rate| rate.effective_from > segment_start && rate.effective_from <= segment_end }
            .map(&:effective_from)
        )

        segment_starts.each_with_index.filter_map do |start_at, index|
          rate = rate_at(start_at)
          next unless rate

          next_start = segment_starts[index + 1]
          end_at = next_start ? [moment_before(next_start), segment_end].min : segment_end
          next if start_at > end_at

          period = BillingPeriods::DatesService::Period.new(
            period_from: start_at,
            period_to: end_at,
            next_billing_at: cycle.next_billing_at,
            rate:,
            cycle:,
            proration_ratio: proration_ratio_for(cycle, start_at, end_at),
            consumed_ratio: consumed_ratio_for(cycle, start_at)
          )

          period if include_period?(period)
        end
      end

      def sorted_rates
        @sorted_rates ||= rates.sort_by(&:effective_from)
      end

      def interval_source_for(cycle_start)
        rate_at(cycle_start) || sorted_rates[rate_index_after(cycle_start)]
      end

      def rate_phase_for_cycle(cycle_index)
        rate_phases.rate_phase_for_cycle(cycle_index)
      end

      def rate_at(datetime)
        index = rate_index_after(datetime)
        return if index.zero?

        sorted_rates[index - 1]
      end

      def rate_index_after(datetime)
        sorted_rates.bsearch_index { |rate| rate.effective_from > datetime } || sorted_rates.size
      end

      def boundaries_for(interval_count, interval_unit, anchor_date: billing_anchor_date)
        @boundaries_by_interval ||= {}
        @boundaries_by_interval[[anchor_date, interval_count, interval_unit]] ||= Boundaries.new(
          billing_anchor_date: anchor_date,
          interval_count:,
          interval_unit:,
          timezone:
        )
      end

      def include_period?(period)
        return true unless exclude_out_of_range

        period.period_to >= range_begin && period.period_from <= range_end
      end

      def proration_ratio_for(cycle, start_at, end_at)
        return 1 unless subscription_rate_card.proration?

        boundaries_by_cycle.fetch(cycle).proration_ratio(start_at, end_at)
      end

      # The consumed ratio represents how much of this period slice has elapsed within
      # the requested range. Advance termination crediting uses this to refund the
      # unused remainder of an already-paid full period.
      def consumed_ratio_for(cycle, start_at)
        boundaries_by_cycle.fetch(cycle).proration_ratio(start_at, range.end)
      end

      def boundaries_by_cycle
        @boundaries_by_cycle ||= {}
      end

      def moment_before(datetime)
        Time.zone.at(datetime.utc.to_r - Rational(1, 1_000_000)).utc
      end

      def range_begin
        @range_begin ||= range.begin.to_date.beginning_of_day.utc
      end

      def range_end
        @range_end ||= range.end.to_date.end_of_day.utc
      end
    end
  end
end
