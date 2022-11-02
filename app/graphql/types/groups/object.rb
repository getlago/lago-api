# frozen_string_literal: true

module Types
  module Groups
    class Object < Types::BaseObject
      graphql_name 'Group'

      field :id, ID, null: false
      field :key, String, null: true
      field :value, String, null: false

      def key
        object.parent&.value
      end
    end
  end
end
