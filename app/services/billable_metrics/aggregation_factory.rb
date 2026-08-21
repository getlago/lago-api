# frozen_string_literal: true

module BillableMetrics
  class AggregationFactory
    def self.new_instance(charge:, current_usage: false, **attributes)
      aggregator_class(charge, current_usage).new(
        event_store_class: Events::Stores::StoreFactory.store_class(organization: charge.billable_metric.organization),
        charge:,
        **attributes
      )
    end

    def self.aggregator_class(charge, current_usage)
      case charge.billable_metric.aggregation_type.to_sym
      when :count_agg
        if current_usage && RealtimeUsage.eligible_charge?(charge)
          BillableMetrics::Aggregations::Realtime::CountService
        else
          BillableMetrics::Aggregations::CountService
        end

      when :latest_agg
        raise(NotImplementedError) if charge.pay_in_advance? && !current_usage

        BillableMetrics::Aggregations::LatestService

      when :max_agg
        raise(NotImplementedError) if charge.pay_in_advance? && !current_usage

        BillableMetrics::Aggregations::MaxService

      when :sum_agg
        if charge.prorated?
          BillableMetrics::ProratedAggregations::SumService
        elsif current_usage && RealtimeUsage.eligible_charge?(charge)
          BillableMetrics::Aggregations::Realtime::SumService
        else
          BillableMetrics::Aggregations::SumService
        end

      when :unique_count_agg
        if charge.prorated?
          BillableMetrics::ProratedAggregations::UniqueCountService
        else
          BillableMetrics::Aggregations::UniqueCountService
        end

      when :weighted_sum_agg
        raise(NotImplementedError) if charge.pay_in_advance? && !current_usage

        BillableMetrics::Aggregations::WeightedSumService

      when :custom_agg
        BillableMetrics::Aggregations::CustomService

      else
        raise(NotImplementedError)
      end
    end
  end
end
