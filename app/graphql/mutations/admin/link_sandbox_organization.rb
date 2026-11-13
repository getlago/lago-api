# frozen_string_literal: true

module Mutations
  module Admin
    class LinkSandboxOrganization < BaseMutation
      # Included first, so the admin checks run before it.
      include RequiresSelfServe
      include AuthenticableAdminUser

      graphql_name "AdminLinkSandboxOrganization"
      description "Turns an existing organization into the sandbox of a production organization"

      input_object_class Types::Admin::LinkSandboxOrganizationInput
      type Types::Admin::LinkSandboxOrganizationPayload

      def resolve(production_organization_id:, sandbox_organization_id:, reason:)
        result = ::Admin::LinkSandboxOrganizationService.call(
          actor: current_user,
          production_organization: Organization.find_by(id: production_organization_id),
          sandbox_organization: Organization.find_by(id: sandbox_organization_id),
          reason:
        )

        result.success? ? result : result_error(result)
      end
    end
  end
end
