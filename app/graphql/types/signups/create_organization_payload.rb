# frozen_string_literal: true

module Types
  module Signups
    class CreateOrganizationPayload < Types::BaseObject
      graphql_name "CreateSelfServeOrganizationPayload"

      field :landing_organization, Types::Organizations::OrganizationType, null: false, method: :sandbox_organization,
        description: "The organization to open after Step 3: the sandbox"
      field :production_organization, Types::Organizations::OrganizationType, null: false, method: :organization
      field :sandbox_organization, Types::Organizations::OrganizationType, null: false
      field :user, Types::UserType, null: false
    end
  end
end
