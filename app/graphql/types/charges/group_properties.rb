# frozen_string_literal: true

module Types
  module Charges
    class GroupProperties < Types::BaseObject
      graphql_name 'GroupProperties'

      field :group_id, ID, null: false
      field :values, Types::Charges::Properties, null: false

      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true
    end
  end
end
