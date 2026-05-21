# frozen_string_literal: true

module Types
  module Admin
    class CreateOrganizationPayload < Types::BaseObject
      graphql_name "AdminCreateOrganizationPayload"

      field :organization, Types::Admin::OrganizationType, null: false
      field :invite_url, String, null: false
    end
  end
end
