# frozen_string_literal: true

module Types
  module Charges
    class GroupProperties < Types::BaseObject
      field :group_id, ID, null: false
      field :invoice_display_name, String, null: true
      field :values, Types::Charges::Properties, null: false

      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true
    end
  end
end
