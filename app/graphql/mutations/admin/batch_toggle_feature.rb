# frozen_string_literal: true

module Mutations
  module Admin
    class BatchToggleFeature < BaseMutation
      include AuthenticableAdminUser

      graphql_name "AdminBatchToggleFeature"
      description "Toggle a feature across multiple organizations"

      argument :enabled, Boolean, required: true
      argument :feature_key, String, required: true
      argument :feature_type, Types::Admin::FeatureTypeEnum, required: true
      argument :notify_org_admin, Boolean, required: true
      argument :organization_ids, [ID], required: true
      argument :reason, String, required: true

      type [Types::Admin::AuditLogType]

      def resolve(organization_ids:, feature_type:, feature_key:, enabled:, reason:, notify_org_admin:)
        organizations = Organization.where(id: organization_ids)
        missing_ids = organization_ids.map(&:to_s) - organizations.pluck(:id)

        if missing_ids.any?
          return validation_error(messages: {organization_ids: missing_ids.map { |id| "#{id}: not_found" }})
        end

        batch_id = SecureRandom.uuid
        audit_logs = []
        error = nil

        ActiveRecord::Base.transaction do
          organizations.each do |organization|
            result = ::Admin::ToggleFeatureService.call(
              actor: current_user,
              organization: organization,
              feature_type: feature_type,
              feature_key: feature_key,
              enabled: enabled,
              reason: reason,
              notify_org_admin: notify_org_admin,
              batch_id: batch_id
            )

            unless result.success?
              error = result_error(result)
              raise ActiveRecord::Rollback
            end

            audit_logs << result.audit_log
          end
        end

        error || audit_logs
      end
    end
  end
end
