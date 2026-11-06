# frozen_string_literal: true

module Types
  module Admin
    class LinkSandboxOrganizationInput < BaseInputObject
      graphql_name "AdminLinkSandboxOrganizationInput"
      description "Link sandbox organization input arguments"

      argument :production_organization_id, ID, required: true
      argument :reason, String, required: true
      argument :sandbox_organization_id, ID, required: true
    end
  end
end
