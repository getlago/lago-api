# frozen_string_literal: true

module BillableMetrics
  class AggregationFactory
    # NOTE: provider is the collaborator that mints the event store instance for this
    #       metered item. Callers that already run one for the whole computation pass
    #       theirs; the others get a degenerate one, scoped to this single aggregation.
    def self.new_instance(metered_item:, context:, current_usage: false, provider: nil, **attributes)
      if provider
        unless provider.scoped_to?(context:, boundaries: attributes[:boundaries])
          raise ArgumentError,
            "event store provider runs on another event context or window than this aggregation"
        end
      else
        provider = Events::Stores::Provider.new(
          organization: metered_item.billable_metric.organization,
          context:,
          boundaries: attributes[:boundaries]
        )
      end

      aggregator_class(metered_item, current_usage).new(
        event_store: provider.store_for(metered_item:, filters: attributes[:filters] || {}),
        metered_item:,
        context:,
        **attributes
      )
    end

    def self.aggregator_class(metered_item, current_usage)
      case metered_item.billable_metric.aggregation_type.to_sym
      when :count_agg
        BillableMetrics::Aggregations::CountService

      when :latest_agg
        raise(NotImplementedError) if metered_item.pay_in_advance? && !current_usage

        BillableMetrics::Aggregations::LatestService

      when :max_agg
        raise(NotImplementedError) if metered_item.pay_in_advance? && !current_usage

        BillableMetrics::Aggregations::MaxService

      when :sum_agg
        if metered_item.prorated?
          BillableMetrics::ProratedAggregations::SumService
        else
          BillableMetrics::Aggregations::SumService
        end

      when :unique_count_agg
        if metered_item.prorated?
          BillableMetrics::ProratedAggregations::UniqueCountService
        else
          BillableMetrics::Aggregations::UniqueCountService
        end

      when :weighted_sum_agg
        raise(NotImplementedError) if metered_item.pay_in_advance? && !current_usage

        BillableMetrics::Aggregations::WeightedSumService

      when :custom_agg
        BillableMetrics::Aggregations::CustomService

      else
        raise(NotImplementedError)
      end
    end
  end
end
