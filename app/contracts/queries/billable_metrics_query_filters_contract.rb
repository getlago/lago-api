# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Queries
  class BillableMetricsQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:recurring).filled(:bool)
      optional(:aggregation_types).array(:string, included_in?: %w[max_agg count_agg])
    end
  end
end
