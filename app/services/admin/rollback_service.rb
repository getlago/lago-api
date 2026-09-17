# frozen_string_literal: true

module Admin
  class RollbackService < ::BaseService
    Result = BaseResult[:audit_log]

    def initialize(actor:, audit_log:, reason:)
      @actor = actor
      @audit_log = audit_log
      @reason = reason
      super()
    end

    def call
      return result.not_found_failure!(resource: "audit_log") unless audit_log

      unless CsAdminAuditLog::TOGGLEABLE_FEATURE_TYPES.include?(audit_log.feature_type)
        return result.single_validation_failure!(
          error_code: "cannot_rollback_organization_creation",
          field: :feature_type
        )
      end

      result.audit_log = ApplyFeatureChangeService.call!(
        actor:,
        organization: audit_log.organization,
        feature_type: audit_log.feature_type,
        feature_key: audit_log.feature_key,
        enabled: audit_log.org_created? ? false : audit_log.before_value,
        reason:,
        rollback_of: audit_log
      ).audit_log

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :actor, :audit_log, :reason
  end
end
