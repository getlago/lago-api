# frozen_string_literal: true

module Mutations
  module Admin
    class RenameOrganization < BaseMutation
      include AuthenticableAdminUser

      graphql_name "AdminRenameOrganization"
      description "Rename an organization"

      argument :name, String, required: true
      argument :organization_id, ID, required: true
      argument :reason, String, required: true

      type Types::Admin::AuditLogType

      def resolve(organization_id:, name:, reason:)
        organization = Organization.find_by(id: organization_id)

        result = ::Admin::RenameOrganizationService.call(
          actor: current_user,
          organization:,
          name:,
          reason:
        )

        result.success? ? result.audit_log : result_error(result)
      end
    end
  end
end
