# frozen_string_literal: true

module Types
  module ProductItems
    class Object < Types::BaseObject
      graphql_name 'ProductItem'

      field :id, ID, null: false
      field :billable_metric, Types::BillableMetrics::Object, null: false
    end
  end
end
