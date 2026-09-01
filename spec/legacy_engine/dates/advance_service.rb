# frozen_string_literal: true

module BillingPeriods
  module Dates
    # Resolves periods billed in advance. With B = the boundary on or before the
    # scheduling range in the customer timezone, advance bills the period starting
    # at B: [B, B + interval). period_to is inclusive and rounded to end_of_day.
    #
    # Example: anchor 2022-02-01, monthly, range 2022-03-01..2022-03-31
    # returns [2022-03-01, 2022-03-31 23:59:59], next 2022-04-01.
    class AdvanceService < BillingPeriods::Dates::BaseService
      private

      def segment_range_for(cycle)
        [cycle.period_from, cycle.period_to]
      end

      def next_billing_at_for(boundaries, boundary_index)
        boundaries.at(boundary_index + 1).utc
      end

      def next_cycle_start_for(cycle)
        cycle.next_billing_at
      end

      def cycle_due?(cycle)
        cycle.period_from <= range_end && cycle.next_billing_at > range_begin
      end

      def cycle_due_after_range?(cycle)
        cycle.period_from > range_end
      end
    end
  end
end
