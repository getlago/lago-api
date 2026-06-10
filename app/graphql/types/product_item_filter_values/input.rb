# frozen_string_literal: true

module Types
  module ProductItemFilterValues
    class Input < BaseInputObject
      graphql_name "ProductItemFilterValueInput"
      description "Product item filter value input arguments"

      argument :billable_metric_filter_id, ID, required: true
      argument :value, String, required: true
    end
  end
end
