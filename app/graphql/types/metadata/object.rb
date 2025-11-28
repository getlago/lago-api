# frozen_string_literal: true

module Types
  module Metadata
    class Object < Types::BaseObject
      graphql_name "ItemMetadata"
      description "Metadata key-value pair"

      field :key, String, null: false
      field :value, String, null: true
    end
  end
end
