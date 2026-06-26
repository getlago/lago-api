# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module BillableMetricFilters
    class Input < BaseInputObject
      graphql_name "BillableMetricFiltersInput"
      description "Billable metric filters input arguments"

      argument :key, String, required: true
      argument :values, [String], required: true
    end
  end
end
