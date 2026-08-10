# frozen_string_literal: true

module Types
  module ProductFilterValues
    class Input < BaseInputObject
      graphql_name "ProductFilterValueInput"
      description "Product filter value input arguments"

      argument :billable_metric_filter_id, ID, required: true
      # Omitted for a key-only selection: the filter matches any value of the key.
      argument :value, String, required: false
    end
  end
end
