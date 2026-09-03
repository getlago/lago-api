# frozen_string_literal: true

module BillableMetrics
  class AggregationFactory
    # NOTE: provider is the collaborator that mints the event store instance for this
    #       charge. Callers that already run one for the whole computation pass theirs;
    #       the others get a degenerate one, scoped to this single aggregation.
    def self.new_instance(charge:, current_usage: false, provider: nil, **attributes)
      if provider
        provider.scoped_to!(subscription: attributes[:subscription], boundaries: attributes[:boundaries])
      else
        provider = Events::Stores::Provider.new(
          organization: charge.billable_metric.organization,
          subscription: attributes[:subscription],
          boundaries: attributes[:boundaries]
        )
      end

      aggregator_class(charge, current_usage).new(
        event_store: provider.store_for(charge:, filters: attributes[:filters] || {}),
        charge:,
        **attributes
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
