# frozen_string_literal: true

module Types
  module Charges
    class GroupPropertiesInput < Types::BaseInputObject
      argument :group_id, ID, required: true
      argument :values, Types::Charges::PropertiesInput, required: true
    end
  end
end
