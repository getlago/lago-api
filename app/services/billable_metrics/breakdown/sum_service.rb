# frozen_string_literal: true

module BillableMetrics
  module Breakdown
    class SumService < BillableMetrics::ProratedAggregations::SumService
      def breakdown(from_datetime:, to_datetime:)
        @from_datetime = from_datetime
        @to_datetime = to_datetime

        breakdown = persisted_breakdown
        breakdown += period_breakdown

        # NOTE: in the breakdown, dates are in customer timezone
        result.breakdown = breakdown.sort_by(&:date)
        result
      end

      private

      attr_reader :from_datetime, :to_datetime

      def from_date_in_customer_timezone
        from_datetime.in_time_zone(customer.applicable_timezone).to_date
      end

      def to_date_in_customer_timezone
        to_datetime.in_time_zone(customer.applicable_timezone).to_date
      end

      def persisted_breakdown
        persisted_sum = persisted_query.sum("(#{sanitized_field_name})::numeric")
        return [] if persisted_sum.zero?

        [
          OpenStruct.new(
            date: from_date_in_customer_timezone,
            action: persisted_sum.negative? ? 'remove' : 'add',
            amount: persisted_sum,
            duration: (to_date_in_customer_timezone + 1.day - from_date_in_customer_timezone).to_i,
            total_duration: period_duration,
          ),
        ]
      end

      def period_breakdown
        date_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'events.timestamp')

        added_list = period_query.group(Arel.sql("DATE(#{date_field})"))
          .order(Arel.sql("DATE(#{date_field}) ASC"))
          .pluck(Arel.sql(
            [
              "DATE(#{date_field}) as date",
              "SUM(CAST(#{sanitized_field_name} AS FLOAT))::numeric",
            ].join(', '),
          ))

        added_list.map do |aggregation|
          OpenStruct.new(
            date: aggregation.first.to_date,
            action: aggregation.last.negative? ? 'remove' : 'add',
            amount: aggregation.last,
            duration: (to_date_in_customer_timezone + 1.day - aggregation.first).to_i,
            total_duration: period_duration,
          )
        end
      end
    end
  end
end
