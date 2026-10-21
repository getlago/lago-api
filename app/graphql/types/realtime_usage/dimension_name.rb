# frozen_string_literal: true

module Types
  module RealtimeUsage
    class DimensionName < Types::BaseObject
      graphql_name "RealtimeUsageDimensionName"
      description "A dimension of a billable metric, without its usage"

      field :key, String, null: false, description: "Opaque key, to pass back as a dimension filter"
      field :name, String, null: true, description: "Null for the usage of no charge filter or pricing group"
    end
  end
end
