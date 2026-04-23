# frozen_string_literal: true

module Types
  module Admin
    class CurrentStaffType < Types::BaseObject
      graphql_name "AdminCurrentStaff"
      description "Metadata about the currently authenticated Lago staff user"

      field :email, String, null: false
      field :role, String, null: false
      field :allowed_integrations, [String], null: false
      field :reason_categories, [Types::Admin::ReasonCategoryEnum], null: false
    end
  end
end
