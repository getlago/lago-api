# frozen_string_literal: true

module Admin
  class FeatureChangeValidator < BaseValidator
    def valid?
      validate_feature
      validate_rollback if args[:rollback_of]

      if ![true, false].include?(args[:enabled])
        add_error(field: :enabled, error_code: "invalid_boolean")
      elsif args[:enabled] == args[:before_value]
        add_error(field: :enabled, error_code: args[:enabled] ? "feature_already_enabled" : "feature_already_disabled")
      end

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    def validate_feature
      unless CsAdminAuditLog::TOGGLEABLE_FEATURE_TYPES.include?(args[:feature_type])
        return add_error(field: :feature_type, error_code: "invalid")
      end

      valid_key = if args[:feature_type] == "premium_integration"
        Organization::PREMIUM_INTEGRATIONS.include?(args[:feature_key])
      else
        FeatureFlag.valid?(args[:feature_key])
      end

      unless valid_key
        add_error(field: :feature_key, error_code: args[:rollback_of] ? "feature_no_longer_available" : "invalid")
      end
    end

    def validate_rollback
      log = args[:rollback_of]

      if log.rollback?
        return add_error(field: :audit_log, error_code: "cannot_rollback_a_rollback")
      end

      if CsAdminAuditLog.exists?(rollback_of_id: log.id)
        return add_error(field: :audit_log, error_code: "already_rolled_back")
      end

      # Reject tied timestamps too: their ordering is ambiguous, so restoring an
      # older state cannot safely be attributed to this entry.
      newer_change = CsAdminAuditLog.where(
        organization_id: log.organization_id,
        feature_type: log.feature_type,
        feature_key: log.feature_key
      ).where.not(id: log.id).where("created_at >= ?", log.created_at).exists?

      if newer_change || args[:before_value] != log.after_value
        add_error(field: :audit_log, error_code: "change_has_been_superseded")
      end
    end
  end
end
