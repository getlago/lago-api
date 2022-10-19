# frozen_string_literal: true

module Types
  module Charges
    class GroupPropertiesInput < Types::BaseInputObject
      graphql_name 'GroupPropertiesInput'

      argument :group_id, ID, required: true
      argument :values, Types::Charges::PropertiesInput, required: true
    end
  end
end
