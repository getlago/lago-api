# frozen_string_literal: true

module Mutations
  module Admin
    class ActivateOrganization < BaseMutation
      # Included first, so the admin checks run before it.
      include RequiresSelfServe
      include AuthenticableAdminUser

      graphql_name "AdminActivateOrganization"
      description "Opens a self-serve production organization that is waiting for a payment method"

      argument :organization_id, ID, required: true
      argument :reason, String, required: true

      type Types::Admin::OrganizationType

      def resolve(organization_id:, reason:)
        result = ::Admin::ActivateOrganizationService.call(
          actor: current_user,
          organization: Organization.find_by(id: organization_id),
          reason:
        )

        result.success? ? result.organization : result_error(result)
      end
    end
  end
end
