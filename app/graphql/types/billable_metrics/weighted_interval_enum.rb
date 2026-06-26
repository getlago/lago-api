# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module BillableMetrics
    class WeightedIntervalEnum < Types::BaseEnum
      BillableMetric::WEIGHTED_INTERVAL.values.each do |type|
        value type
      end
    end
  end
end
