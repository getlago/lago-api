# frozen_string_literal: true

module Types
  module UsageAttributionTypes
    class UpdateInput < BaseInputObject
      description "Update usage attribution type input arguments"

      argument :id, ID, required: true

      argument :attribution_key, String, required: false
      argument :code, String, required: false
      argument :name, String, required: false
      argument :parent_id, ID, required: false
      argument :role, Types::UsageAttributionTypes::RoleEnum, required: false
    end
  end
end
