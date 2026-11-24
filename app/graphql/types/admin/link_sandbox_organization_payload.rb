# frozen_string_literal: true

module Types
  module Admin
    class LinkSandboxOrganizationPayload < Types::BaseObject
      graphql_name "AdminLinkSandboxOrganizationPayload"

      field :organization, Types::Admin::OrganizationType, null: false
      field :sandbox_organization, Types::Admin::OrganizationType, null: false
    end
  end
end
