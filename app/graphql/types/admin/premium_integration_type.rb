# frozen_string_literal: true

module Types
  module Admin
    class PremiumIntegrationType < Types::BaseObject
      graphql_name "AdminPremiumIntegration"
      description "A premium integration available to toggle on an organization"

      field :name, String, null: false
      field :allowed_for_current_user, Boolean, null: false
    end
  end
end
