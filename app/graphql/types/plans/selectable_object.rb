# frozen_string_literal: true

module Types
  module Plans
    class SelectableObject < Types::BaseObject
      graphql_name "SelectablePlan"
      description "Minimal plan fields for selection inputs"

      field :id, ID, null: false

      field :code, String, null: false
      field :name, String, null: false
    end
  end
end
