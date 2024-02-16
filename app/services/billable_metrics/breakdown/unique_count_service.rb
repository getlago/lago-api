# frozen_string_literal: true

module BillableMetrics
  module Breakdown
    class UniqueCountService < BillableMetrics::ProratedAggregations::UniqueCountService
      def breakdown
        breakdown = event_store.prorated_unique_count_breakdown(with_remove: true)
          .group_by { |r| r['property'] }
          .map do |_, rows|
            row = rows.first
            operation_type = row['operation_type']

            # NOTE: breakdown, is based only on the current period
            datetime = (row['timestamp'] < from_datetime) ? from_datetime : row['timestamp']

            if rows.count > 1 # NOTE: add then remove
              operation_type = (row['timestamp'] < from_datetime) ? 'remove' : 'add_and_removed'
              datetime = rows.last['timestamp'] unless operation_type == 'add_and_removed'
            end

            OpenStruct.new(
              date: datetime.in_time_zone(customer.applicable_timezone).to_date,
              action: operation_type,
              amount: row['prorated_value'].ceil,
              duration: ((to_datetime - from_datetime).fdiv(1.day).round * row['prorated_value']).round,
              total_duration: period_duration,
            )
          end

        # NOTE: in the breakdown, dates are in customer timezone
        result.breakdown = breakdown.sort_by(&:date)
        result
      end
    end
  end
end
