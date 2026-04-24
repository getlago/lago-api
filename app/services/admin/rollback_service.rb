# frozen_string_literal: true

module Admin
  class RollbackService < ::BaseService
    Result = BaseResult[:audit_log]

    def initialize(actor:, audit_log:, reason:)
      @actor = actor
      @audit_log = audit_log
      @reason = reason
      super
    end

    def call
      return result.not_found_failure!(resource: "audit_log") unless audit_log

      organization = audit_log.organization
      reversed_enabled = !audit_log.after_value
      current_value = currently_enabled?(organization)

      ActiveRecord::Base.transaction do
        apply_toggle!(organization, reversed_enabled)

        rollback_log = CsAdminAuditLog.create!(
          actor_user: actor,
          actor_email: actor.email,
          action: :rollback,
          organization: organization,
          feature_type: audit_log.feature_type,
          feature_key: audit_log.feature_key,
          before_value: current_value,
          after_value: reversed_enabled,
          reason: reason,
          rollback_of: audit_log,
          batch_id: audit_log.batch_id
        )

        result.audit_log = rollback_log
      end

      Admin::SlackNotificationJob.perform_later(result.audit_log.id)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :actor, :audit_log, :reason

    def currently_enabled?(organization)
      if audit_log.premium_integration?
        organization.premium_integrations.include?(audit_log.feature_key)
      else
        organization.feature_flag_enabled?(audit_log.feature_key)
      end
    end

    def apply_toggle!(organization, enabled)
      if audit_log.premium_integration?
        if enabled
          organization.update!(premium_integrations: (organization.premium_integrations + [audit_log.feature_key]).uniq)
        else
          organization.update!(premium_integrations: organization.premium_integrations - [audit_log.feature_key])
        end
      elsif enabled
        organization.enable_feature_flag!(audit_log.feature_key)
      else
        organization.disable_feature_flag!(audit_log.feature_key)
      end
    end
  end
end
