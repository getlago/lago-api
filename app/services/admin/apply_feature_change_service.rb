# frozen_string_literal: true

module Admin
  class ApplyFeatureChangeService < ::BaseService
    Result = BaseResult[:audit_log]

    def initialize(actor:, organization:, feature_type:, feature_key:, enabled:, reason:, notify_org_admin: false, rollback_of: nil)
      @actor = actor
      @organization = organization
      @feature_type = feature_type.to_s
      @feature_key = feature_key.to_s
      @enabled = enabled
      @reason = reason
      @notify_org_admin = notify_org_admin
      @rollback_of = rollback_of
      super()
    end

    def call
      return result.not_found_failure!(resource: "organization") unless organization

      organization.with_lock do
        before_value = current_features.include?(feature_key)
        validator = FeatureChangeValidator.new(
          result, feature_type:, feature_key:, enabled:, before_value:, rollback_of:
        )
        next unless validator.valid?

        audit_log = CsAdminAuditLog.new(
          actor_user: actor,
          actor_email: actor.email,
          action: action,
          organization:,
          feature_type:,
          feature_key:,
          before_value:,
          after_value: enabled,
          reason:,
          rollback_of:,
          batch_id: rollback_of&.batch_id
        )
        audit_log.validate!

        update_feature!
        audit_log.save!
        result.audit_log = audit_log

        after_commit do
          Admin::SlackNotificationJob.perform_later(audit_log.id)
          AdminMailer.feature_toggled(audit_log:).deliver_later if notify_org_admin
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :actor, :organization, :feature_type, :feature_key, :enabled, :reason, :notify_org_admin, :rollback_of

    def action
      if rollback_of
        :rollback
      else
        enabled ? :toggle_on : :toggle_off
      end
    end

    def current_features
      (feature_type == "premium_integration") ? organization.premium_integrations : organization.feature_flags
    end

    def update_feature!
      if feature_type == "premium_integration"
        features = enabled ? current_features | [feature_key] : current_features - [feature_key]
        organization.update!(premium_integrations: features)
      elsif enabled
        organization.enable_feature_flag!(feature_key)
      else
        organization.disable_feature_flag!(feature_key)
      end
    end
  end
end
