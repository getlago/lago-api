# frozen_string_literal: true

module Types
  module RealtimeUsage
    class Dimension < Types::BaseObject
      graphql_name "RealtimeUsageDimension"
      description "A charge filter or pricing group value a usage is split on, and its window total"

      field :key, String, null: false, description: "Opaque key, to pass back as a dimension filter, except on the folded series"
      field :name, String, null: true, description: "Null for the usage of no charge filter or pricing group"
      field :other, Boolean, null: false, description: "True for the series folding every dimension past the biggest ones"
      field :units, GraphQL::Types::Float, null: false
    end
  end
end
