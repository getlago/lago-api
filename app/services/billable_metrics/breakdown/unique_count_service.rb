# frozen_string_literal: true

module BillableMetrics
  module Breakdown
    class UniqueCountService < BillableMetrics::ProratedAggregations::UniqueCountService
      def breakdown(from_datetime:, to_datetime:)
        @from_datetime = from_datetime
        @to_datetime = to_datetime

        breakdown = persisted_breakdown
        breakdown += added_breakdown
        breakdown += removed_breadown
        breakdown += added_and_removed_breakdown

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
        persisted_count = prorated_persisted_query.count
        return [] if persisted_count.zero?

        [
          OpenStruct.new(
            date: from_date_in_customer_timezone,
            action: 'add',
            amount: persisted_count,
            duration: (to_date_in_customer_timezone + 1.day - from_date_in_customer_timezone).to_i,
            total_duration: period_duration,
          ),
        ]
      end

      def added_breakdown
        date_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'quantified_events.added_at')

        added_list = prorated_added_query.group(Arel.sql("DATE(#{date_field})"))
                                         .order(Arel.sql("DATE(#{date_field}) ASC"))
                                         .pluck(Arel.sql(
                                           [
                                             "DATE(#{date_field}) as date",
                                             'COUNT(quantified_events.id) as metric_count',
                                          ].join(', '),
                                         ))

        added_list.map do |aggregation|
          OpenStruct.new(
            date: aggregation.first.to_date,
            action: 'add',
            amount: aggregation.last,
            duration: (to_date_in_customer_timezone + 1.day - aggregation.first).to_i,
            total_duration: period_duration,
          )
        end
      end

      def removed_breadown
        date_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'quantified_events.removed_at')

        removed_list = prorated_removed_query.group(Arel.sql("DATE(#{date_field})"))
                                             .order(Arel.sql("DATE(#{date_field}) ASC"))
                                             .pluck(Arel.sql(
                                              [
                                                "DATE(#{date_field}) as date",
                                                'COUNT(quantified_events.id) as metric_count',
                                              ].join(', '),
                                              ))

        removed_list.map do |aggregation|
          OpenStruct.new(
            date: aggregation.first.to_date,
            action: 'remove',
            amount: aggregation.last,
            duration: (aggregation.first + 1.day - from_date_in_customer_timezone).to_i,
            total_duration: period_duration,
          )
        end
      end

      def added_and_removed_breakdown
        added_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'quantified_events.added_at')
        removed_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'quantified_events.removed_at')

        added_and_removed_list = prorated_added_and_removed_query.group(
          Arel.sql("DATE(#{added_field}), DATE(#{removed_field})"),
          ).order(
          Arel.sql("DATE(#{added_field}) ASC, DATE(#{removed_field}) ASC"),
          ).pluck(Arel.sql(
          [
            "DATE(#{added_field}) as added_at",
            "DATE(#{removed_field}) as removed_at",
            'COUNT(quantified_events.id) as metric_count',
          ].join(', '),
        ))

        added_and_removed_list.map do |aggregation|
          OpenStruct.new(
            date: aggregation.first.to_date,
            action: 'add_and_removed',
            amount: aggregation.last,
            duration: (aggregation.second.to_date + 1.day - aggregation.first.to_date).to_i,
            total_duration: period_duration,
          )
        end
      end
    end
  end
end
