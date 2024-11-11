# frozen_string_literal: true

module Queries
  class BillableMetricsQueryFiltersContract < Dry::Validation::Contract
    params do
      required(:filters).hash do
        optional(:recurring).filled(:bool)
        optional(:aggregation_types).array(:string, included_in?: %w[max_agg count_agg])
      end

      optional(:search_term).maybe(:string)
    end
  end
end
