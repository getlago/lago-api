# frozen_string_literal: true

module Types
  module Admin
    class CreateOrganizationPayload < Types::BaseObject
      graphql_name "AdminCreateOrganizationPayload"

      field :invite_url, String, null: false
      field :organization, Types::Admin::OrganizationType, null: false
    end
  end
end
