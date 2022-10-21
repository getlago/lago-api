# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class BaseService < ::BaseService
      def initialize(billable_metric:, subscription:)
        super(nil)
        @billable_metric = billable_metric
        @subscription = subscription
      end

      def aggregate(from_date:, to_date:, options: {})
        raise NotImplementedError
      end

      protected

      attr_accessor :billable_metric, :subscription

      delegate :customer, to: :subscription

      def events_scope(from_date:, to_date:)
        subscription.events
          .from_date(from_date)
          .to_date(to_date)
          .where(code: billable_metric.code)
      end

      def groups
        billable_metric.selectable_groups.pluck(:key).uniq
      end

      def sanitized_name(property)
        ActiveRecord::Base.sanitize_sql_for_conditions(
          ['events.properties->>?', property],
        )
      end

      def sanitized_field_name
        sanitized_name(billable_metric.field_name)
      end

      def aggregation_per_group(events, aggregation_select)
        groups.map do |group|
          events.select(
            "(#{aggregation_select}) as group_agg, #{sanitized_name(group)} as group_name",
          ).group(
            sanitized_name(group),
          ).map do |e|
            { e.group_name => e.group_agg } if e.group_name
          end.compact
        end
      end
    end
  end
end
