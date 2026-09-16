# frozen_string_literal: true

module Types
  module UsageAttributionTypes
    class CreateInput < BaseInputObject
      description "Create usage attribution type input arguments"

      argument :attribution_key, String, required: true
      argument :code, String, required: true
      argument :name, String, required: false
      argument :parent_id, ID, required: false
      argument :role, Types::UsageAttributionTypes::RoleEnum, required: true
    end
  end
end
