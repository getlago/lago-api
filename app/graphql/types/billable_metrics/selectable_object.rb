# frozen_string_literal: true

module Types
  module BillableMetrics
    class SelectableObject < Types::BaseObject
      graphql_name "SelectableBillableMetric"
      description "Minimal billable metric fields for selection inputs"

      field :id, ID, null: false

      field :code, String, null: false
      field :name, String, null: false
    end
  end
end
