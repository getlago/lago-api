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

      ActiveRecord::Base.transaction do
        # Refuses a sandbox once the row is locked and reloaded, so a toggle that waited behind a link sees it.
        ::Organizations::SandboxLockService.call!(organization:)

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
          # Shared with the rows of the sandbox copy, which the Slack message names.
          batch_id: rollback_of&.batch_id || (SecureRandom.uuid if Organization.exists?(production_organization_id: organization.id))
        )
        audit_log.validate!

        update_feature!
        audit_log.save!
        result.audit_log = audit_log
        mirror_to_sandbox(audit_log)

        after_commit do
          Admin::SlackNotificationJob.perform_later(audit_log.id)
          AdminMailer.feature_toggled(audit_log:).deliver_later if notify_org_admin
          ApiKeys::CacheService.expire_all_cache(organization)
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :actor, :organization, :feature_type, :feature_key, :enabled, :reason, :notify_org_admin, :rollback_of

    # One audit row per setting the sandbox gained or lost, in the batch of the production row.
    def mirror_to_sandbox(audit_log)
      sync = ::Organizations::SyncSandboxSettingsService.call!(organization:, actor:)
      return unless sync.sandbox_organization

      {premium_integrations: "premium_integration", feature_flags: "feature_flag"}.each do |setting, type|
        change = sync.changes[setting] || next
        change[:added].each { mirror_audit_log(sync.sandbox_organization, audit_log, type, it, added: true) }
        change[:removed].each { mirror_audit_log(sync.sandbox_organization, audit_log, type, it, added: false) }
      end
    end

    def mirror_audit_log(sandbox, audit_log, type, key, added:)
      CsAdminAuditLog.create!(
        actor_user: actor,
        actor_email: actor.email,
        action: added ? :toggle_on : :toggle_off,
        organization: sandbox,
        feature_type: type,
        feature_key: key,
        before_value: !added,
        after_value: added,
        reason:,
        batch_id: audit_log.batch_id
      )
    end

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
