# frozen_string_literal: true

module BillingPeriods
  module Dates
    # Resolves periods billed in arrears. With B = the boundary on or before the
    # scheduling range in the customer timezone, arrears bills the period that just
    # closed: [B - interval, B). period_to is inclusive and rounded to end_of_day.
    #
    # Example: anchor 2022-02-01, monthly, range 2022-03-01..2022-03-01
    # returns [2022-02-01, 2022-02-28 23:59:59], next 2022-04-01.
    class ArrearsService < BaseService
      private

      def segment_start_for(current_rate)
        [started_at.utc, current_rate.effective_from.utc].compact.max
      end

      def segment_end_for(next_rate)
        rate_segment_end(next_rate)
      end

      def starting_index(boundaries, _segment_start)
        boundaries.index_on_or_before(range_begin.in_time_zone(timezone))
      end

      def generation_end(_segment_end)
        range_end
      end

      def period_index(index)
        index - 1
      end
    end
  end
end
