# frozen_string_literal: true

module Types
  module Connections
    class Object < Types::BaseObject
      graphql_name "ConnectionRouting"
      description "The connection a billing object routes to for one category, and where that choice came from"

      field :behavior, Types::Connections::ResolvedBehaviorEnum, null: false
      field :category, Types::Connections::CategoryEnum, null: false
      field :code, String, null: true,
        description: "Code of the connection in effect. Null when the category is skipped or nothing resolves"
    end
  end
end
