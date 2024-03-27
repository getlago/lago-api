# frozen_string_literal: true

module Types
  module Groups
    class Object < Types::BaseObject
      graphql_name "Group"

      field :id, ID, null: false
      field :key, String, null: true
      field :value, String, null: false

      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true

      def key
        object.parent&.value
      end
    end
  end
end
