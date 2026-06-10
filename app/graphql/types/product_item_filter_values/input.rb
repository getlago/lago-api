# frozen_string_literal: true

module Types
  module ProductItemFilterValues
    class Input < BaseInputObject
      graphql_name "ProductItemFilterValueInput"
      description "Product item filter value input arguments"

      argument :billable_metric_filter_id, ID, required: true
      # Omitted for a key-only selection: the filter matches any value of the key.
      argument :value, String, required: false
    end
  end
end
