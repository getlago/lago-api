# frozen_string_literal: true

module Types
  module ProductItemFilterValues
    class Object < Types::BaseObject
      graphql_name "ProductItemFilterValue"
      description "A key/value pair of a product item filter"

      dataload_association :billable_metric_filter

      field :id, ID, null: false

      field :billable_metric_filter, Types::BillableMetricFilters::Object, null: false
      field :key, String, null: false
      field :value, String, null: false
    end
  end
end
