# frozen_string_literal: true

module Types
  module Charges
    class GroupProperties < Types::BaseObject
      graphql_name 'GroupProperties'

      field :group_id, ID, null: false
      field :values, Types::Charges::Properties, null: false
    end
  end
end
