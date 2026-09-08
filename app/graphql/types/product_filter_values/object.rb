# frozen_string_literal: true

module Types
  module ProductFilterValues
    class Object < Types::BaseObject
      graphql_name "ProductFilterValue"
      description "A key/value pair of a product filter"

      dataload_association :billable_metric_filter

      field :id, ID, null: false

      field :billable_metric_filter, Types::BillableMetricFilters::Object, null: false
      field :key, String, null: false
      # Null for a key-only selection: the filter matches any value of the key.
      field :value, String, null: true
    end
  end
end
