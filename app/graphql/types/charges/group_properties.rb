# frozen_string_literal: true

module Types
  module Charges
    class GroupProperties < Types::BaseObject
      field :group_id, ID, null: false
      field :values, Types::Charges::Properties, null: false

      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true
    end
  end
end
