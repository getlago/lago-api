# frozen_string_literal: true

module BillableMetrics
  class AggregationFactory
    CLICKHOUSE_READY = %i[count_agg latest_agg max_agg].freeze

    class << self
      def supports_clickhouse?
        ENV['LAGO_CLICKHOUSE_ENABLED'].present?
      end

      def clickhouse_ready?(aggregation_type)
        CLICKHOUSE_READY.include?(aggregation_type.to_sym)
      end
    end

    def self.new_instance(charge:, current_usage: false, **attributes)
      event_store = Events::Stores::PostgresStore

      if !charge.pay_in_advance? &&
         supports_clickhouse? &&
         charge.billable_metric.organization.clickhouse_aggregation? &&
         clickhouse_ready?(charge.billable_metric.aggregation_type)
        event_store = Events::Stores::ClickhouseStore
      end

      aggregator_class(charge, current_usage).new(
        event_store_class: event_store,
        charge:,
        **attributes,
      )
    end

    def self.aggregator_class(charge, current_usage)
      case charge.billable_metric.aggregation_type.to_sym
      when :count_agg
        BillableMetrics::Aggregations::CountService

      when :latest_agg
        raise(NotImplementedError) if charge.pay_in_advance? && !current_usage

        BillableMetrics::Aggregations::LatestService

      when :max_agg
        raise(NotImplementedError) if charge.pay_in_advance? && !current_usage

        BillableMetrics::Aggregations::MaxService

      when :sum_agg
        if charge.prorated?
          BillableMetrics::ProratedAggregations::SumService
        else
          BillableMetrics::Aggregations::SumService
        end

      when :unique_count_agg
        if charge.prorated?
          BillableMetrics::ProratedAggregations::UniqueCountService
        else
          BillableMetrics::Aggregations::UniqueCountService
        end

      when :recurring_count_agg
        raise(NotImplementedError) if charge.pay_in_advance? && !current_usage

        BillableMetrics::Aggregations::RecurringCountService

      when :weighted_sum_agg
        raise(NotImplementedError) if charge.pay_in_advance? && !current_usage

        BillableMetrics::Aggregations::WeightedSumService

      else
        raise(NotImplementedError)
      end
    end
  end
end
