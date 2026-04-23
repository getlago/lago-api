# frozen_string_literal: true

module Admin
  class ToggleFeatureService < ::BaseService
    Result = BaseResult[:audit_log]

    def initialize(actor:, organization:, feature_type:, feature_key:, enabled:, reason:, notify_org_admin:, batch_id: nil)
      @actor = actor
      @organization = organization
      @feature_type = feature_type
      @feature_key = feature_key
      @enabled = enabled
      @reason = reason
      @notify_org_admin = notify_org_admin
      @batch_id = batch_id
      super
    end

    def call
      return result.not_found_failure!(resource: "organization") unless organization
      return result.validation_failure!(errors: {feature_key: ["invalid"]}) unless valid_feature_key?

      before_value = currently_enabled?

      ActiveRecord::Base.transaction do
        toggle_feature!

        audit_log = CsAdminAuditLog.create!(
          actor_user: actor,
          actor_email: actor.email,
          action: enabled ? :toggle_on : :toggle_off,
          organization: organization,
          feature_type: feature_type,
          feature_key: feature_key,
          before_value: before_value,
          after_value: enabled,
          reason: reason,
          batch_id: batch_id
        )

        result.audit_log = audit_log
      end

      Admin::SlackNotificationJob.perform_later(result.audit_log.id)
      Admin::EmailNotificationJob.perform_later(result.audit_log.id, actor.email) if notify_org_admin

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :actor, :organization, :feature_type, :feature_key, :enabled, :reason, :notify_org_admin, :batch_id

    def valid_feature_key?
      if feature_type == "premium_integration"
        Organization::PREMIUM_INTEGRATIONS.include?(feature_key)
      else
        FeatureFlag.valid?(feature_key)
      end
    end

    def currently_enabled?
      if feature_type == "premium_integration"
        organization.premium_integrations.include?(feature_key)
      else
        organization.feature_flag_enabled?(feature_key)
      end
    end

    def toggle_feature!
      if feature_type == "premium_integration"
        if enabled
          organization.update!(premium_integrations: (organization.premium_integrations + [feature_key]).uniq)
        else
          organization.update!(premium_integrations: organization.premium_integrations - [feature_key])
        end
      elsif enabled
        organization.enable_feature_flag!(feature_key)
      else
        organization.disable_feature_flag!(feature_key)
      end
    end
  end
end
