# frozen_string_literal: true

module BillingPeriods
  module Dates
    # Resolves every period overlapping a termination range, regardless of billing
    # timing. The caller owns whether those periods become final fees, credits, or both.
    class TerminationService < BillingPeriods::Dates::BaseService
      private

      def segment_range_for(cycle)
        [cycle.period_from, [cycle.period_to, range.end.utc].min]
      end

      def next_billing_at_for(boundaries, boundary_index)
        boundaries.at(boundary_index + 1).utc
      end

      def next_cycle_start_for(cycle)
        cycle.period_to.in_time_zone(timezone).to_date.next_day.beginning_of_day.utc
      end

      def cycle_due?(cycle)
        cycle.period_to >= range_begin && cycle.period_from <= range_end
      end

      def cycle_due_after_range?(cycle)
        cycle.period_from > range_end
      end
    end
  end
end
