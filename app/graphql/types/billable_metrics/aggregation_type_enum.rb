# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module BillableMetrics
    class AggregationTypeEnum < Types::BaseEnum
      BillableMetric::AGGREGATION_TYPES.keys.each do |type|
        value type
      end
    end
  end
end
