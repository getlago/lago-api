# frozen_string_literal: true

module Types
  module AttributedUsage
    class Row < Types::AttributedUsage::Aggregate
      graphql_name "AttributedUsageRow"

      field :rank, Integer, null: false, description: "Position of the value in the whole level"
      field :value, String, null: false
    end
  end
end
