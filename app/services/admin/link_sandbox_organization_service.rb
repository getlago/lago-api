# frozen_string_literal: true

module Admin
  # Links a sandbox for a CS admin, with an audit row on each organization and one Slack notification.
  class LinkSandboxOrganizationService < ::BaseService
    include SandboxMirrorAuditLogs

    Result = BaseResult[:organization, :sandbox_organization]

    def initialize(actor:, production_organization:, sandbox_organization:, reason:)
      @actor = actor
      @production_organization = production_organization
      @sandbox_organization = sandbox_organization
      @reason = reason
      super()
    end

    def call
      # Checked before the link takes its locks and copies anything, as the rows are written last.
      if production_organization && sandbox_organization
        audit_log(sandbox_organization, production_organization.id, nil).validate!
      end

      ActiveRecord::Base.transaction do
        link = ::Organizations::LinkSandboxService.call!(production_organization:, sandbox_organization:, actor:)
        create_audit_logs!(link.organization, link.sandbox_organization, link.settings_changes)

        result.organization = link.organization
        result.sandbox_organization = link.sandbox_organization
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :actor, :production_organization, :sandbox_organization, :reason

    # A row on each organization, so the link shows in both histories, and one on the sandbox per feature it copied.
    def create_audit_logs!(production, sandbox, settings_changes)
      batch_id = SecureRandom.uuid
      sandbox_row = audit_log(sandbox, production.id, batch_id)
      sandbox_row.save!
      audit_log(production, sandbox.id, batch_id).save!
      mirror_audit_logs!(sandbox, mirrored_changes(settings_changes), batch_id:)

      after_commit { Admin::SlackNotificationJob.perform_later(sandbox_row.id) }
    end

    def audit_log(organization, feature_key, batch_id)
      CsAdminAuditLog.new(
        actor_user: actor,
        actor_email: actor.email,
        action: :sandbox_linked,
        organization:,
        feature_type: :organization,
        feature_key:,
        before_value: false,
        after_value: true,
        reason:,
        batch_id:
      )
    end
  end
end
