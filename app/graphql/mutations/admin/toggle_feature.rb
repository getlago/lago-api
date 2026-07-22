# frozen_string_literal: true

module Mutations
  module Admin
    class ToggleFeature < BaseMutation
      include AuthenticableAdminUser

      graphql_name "AdminToggleFeature"
      description "Toggle a feature flag or premium integration for an organization"

      argument :enabled, Boolean, required: true
      argument :feature_key, String, required: true
      argument :feature_type, Types::Admin::FeatureTypeEnum, required: true
      argument :notify_org_admin, Boolean, required: true
      argument :organization_id, ID, required: true
      argument :reason, String, required: true

      type Types::Admin::AuditLogType

      def resolve(organization_id:, feature_type:, feature_key:, enabled:, reason:, notify_org_admin:)
        organization = Organization.find_by(id: organization_id)

        result = ::Admin::ToggleFeatureService.new(
          actor: current_user,
          organization: organization,
          feature_type: feature_type,
          feature_key: feature_key,
          enabled: enabled,
          reason: reason,
          notify_org_admin: notify_org_admin
        ).call

        result.success? ? result.audit_log : result_error(result)
      end
    end
  end
end
