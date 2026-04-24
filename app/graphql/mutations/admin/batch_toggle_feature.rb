# frozen_string_literal: true

module Mutations
  module Admin
    class BatchToggleFeature < BaseMutation
      include AuthenticableAdminUser

      graphql_name "AdminBatchToggleFeature"
      description "Toggle a feature across multiple organizations"

      argument :organization_ids, [ID], required: true
      argument :feature_type, Types::Admin::FeatureTypeEnum, required: true
      argument :feature_key, String, required: true
      argument :enabled, Boolean, required: true
      argument :reason, String, required: true
      argument :notify_org_admin, Boolean, required: true

      type [Types::Admin::AuditLogType]

      def resolve(organization_ids:, feature_type:, feature_key:, enabled:, reason:, notify_org_admin:)
        batch_id = SecureRandom.uuid
        audit_logs = []

        organization_ids.each do |org_id|
          organization = Organization.find_by(id: org_id)
          next unless organization

          result = ::Admin::ToggleFeatureService.new(
            actor: current_user,
            organization: organization,
            feature_type: feature_type,
            feature_key: feature_key,
            enabled: enabled,
            reason: reason,
            notify_org_admin: notify_org_admin,
            batch_id: batch_id
          ).call

          return result_error(result) unless result.success?

          audit_logs << result.audit_log
        end

        audit_logs
      end
    end
  end
end
