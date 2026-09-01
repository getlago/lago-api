# frozen_string_literal: true

module BillingPeriods
  module Dates
    # Resolves periods billed in arrears. With B = the boundary on or before the
    # scheduling range in the customer timezone, arrears bills the period that just
    # closed: [B - interval, B). period_to is inclusive and rounded to end_of_day.
    #
    # Example: anchor 2022-02-01, monthly, range 2022-03-01..2022-03-01
    # returns [2022-02-01, 2022-02-28 23:59:59], next 2022-04-01.
    class ArrearsService < BillingPeriods::Dates::BaseService
      private

      def segment_range_for(cycle)
        [cycle.period_from, cycle.period_to]
      end

      def next_billing_at_for(boundaries, boundary_index)
        boundaries.at(boundary_index + 2).utc
      end

      def next_cycle_start_for(cycle)
        cycle_due_at(cycle)
      end

      def cycle_due?(cycle)
        cycle_due_at(cycle) <= range_end && cycle.next_billing_at > range_begin
      end

      def cycle_due_after_range?(cycle)
        cycle_due_at(cycle) > range_end
      end

      def cycle_due_at(cycle)
        cycle.period_to.in_time_zone(timezone).to_date.next_day.beginning_of_day.utc
      end
    end
  end
end
