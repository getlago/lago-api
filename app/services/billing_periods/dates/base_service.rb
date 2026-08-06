# frozen_string_literal: true

module BillingPeriods
  module Dates
    class BaseService < ::BaseService
      Result = BaseResult[:next_billing_at, :periods]

      def initialize(billing_anchor_date:, timezone:, started_at:, rates:, range:, exclude_out_of_range: false)
        @billing_anchor_date = billing_anchor_date
        @timezone = timezone
        @started_at = started_at
        @rates = rates
        @range = range
        @exclude_out_of_range = exclude_out_of_range
        super
      end

      def call
        periods, next_billing_at = periods_and_next_billing_at
        result.periods = periods
        result.next_billing_at = next_billing_at
        result
      end

      private

      attr_reader :billing_anchor_date, :timezone, :started_at, :rates, :range, :exclude_out_of_range

      def periods_and_next_billing_at
        periods = []
        next_billing_at = nil

        rates.each_with_index do |current_rate, index|
          rate_periods, rate_next_billing_at = periods_for_rate(current_rate, rates[index + 1])
          periods.concat(rate_periods)
          next_billing_at = [next_billing_at, rate_next_billing_at].compact.max
        end

        [periods, next_billing_at]
      end

      def periods_for_rate(current_rate, next_rate)
        current_boundaries = boundaries_for(current_rate)
        segment_start = segment_start_for(current_rate)
        segment_end = segment_end_for(next_rate)
        return [[], nil] if segment_end && segment_start > segment_end

        index = starting_index(current_boundaries, segment_start)
        generated_periods = []
        next_billing_at = nil

        loop do
          break if current_boundaries.at(index).utc > generation_end(segment_end)

          period_next_billing_at = current_boundaries.at(index + 1).utc
          next_billing_at = [next_billing_at, period_next_billing_at].compact.max

          period = period_from_boundaries(
            boundaries: current_boundaries,
            index:,
            segment_start:,
            segment_end: segment_end || far_future,
            rate: current_rate
          )

          if period && include_period?(period)
            generated_periods << period
          end

          index += 1
        end

        [generated_periods, next_billing_at]
      end

      def period_from_boundaries(boundaries:, index:, segment_start:, segment_end:, rate:)
        period_index = period_index(index)
        full_period_from = boundaries.at(period_index).utc
        full_period_to = (boundaries.at(period_index + 1) - 1.second).end_of_day.utc
        period_from = [full_period_from, segment_start].max
        period_to = [full_period_to, segment_end].min

        return if period_from > period_to

        BillingPeriods::DatesService::Period.new(
          period_from:,
          period_to:,
          next_billing_at: boundaries.at(index + 1).utc,
          rate:
        )
      end

      def boundaries_for(rate)
        @boundaries_by_interval ||= {}
        key = [rate.billing_interval_count, rate.billing_interval_unit]

        @boundaries_by_interval[key] ||= Boundaries.new(
          billing_anchor_date:,
          interval_count: rate.billing_interval_count,
          interval_unit: rate.billing_interval_unit,
          timezone:
        )
      end

      def rate_segment_end(next_rate)
        return unless next_rate

        Time.zone.at(next_rate.effective_from.utc.to_r - Rational(1, 1_000_000)).utc
      end

      def include_period?(period)
        return true unless exclude_out_of_range

        period.period_to >= range_begin && period.period_from <= range_end
      end

      def range_begin
        @range_begin ||= range.begin.to_date.beginning_of_day.utc
      end

      def range_end
        @range_end ||= range.end.to_date.end_of_day.utc
      end

      def far_future
        @far_future ||= Time.zone.parse("9999-12-31").utc
      end
    end
  end
end
