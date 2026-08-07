# frozen_string_literal: true

module BillingPeriods
  module Dates
    # Resolves periods billed in advance. With B = the boundary on or before the
    # scheduling range in the customer timezone, advance bills the period starting
    # at B: [B, B + interval). period_to is inclusive and rounded to end_of_day.
    #
    # Example: anchor 2022-02-01, monthly, range 2022-03-01..2022-03-31
    # returns [2022-03-01, 2022-03-31 23:59:59], next 2022-04-01.
    class AdvanceService < BaseService
      private

      def segment_start_for(current_rate)
        [range_begin, started_at.utc, current_rate.effective_from.utc].compact.max
      end

      def segment_end_for(next_rate)
        [range_end, rate_segment_end(next_rate)].compact.min
      end

      def starting_index(boundaries, segment_start)
        boundaries.index_on_or_before(segment_start.in_time_zone(timezone))
      end

      def generation_end(segment_end)
        segment_end
      end

      def period_index(index)
        index
      end
    end
  end
end
