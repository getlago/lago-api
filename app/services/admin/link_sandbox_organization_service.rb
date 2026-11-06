# frozen_string_literal: true

module Admin
  # Links a sandbox for a CS admin, with an audit row on each organization and one Slack notification.
  class LinkSandboxOrganizationService < ::BaseService
    Result = BaseResult[:organization, :sandbox_organization]

    def initialize(actor:, production_organization:, sandbox_organization:, reason:)
      @actor = actor
      @production_organization = production_organization
      @sandbox_organization = sandbox_organization
      @reason = reason
      super()
    end

    def call
      ActiveRecord::Base.transaction do
        link = ::Organizations::LinkSandboxService.call!(production_organization:, sandbox_organization:, actor:)
        create_audit_logs!(link.organization, link.sandbox_organization)

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

    # Two rows, so the link shows in the history of both organizations.
    def create_audit_logs!(production, sandbox)
      batch_id = SecureRandom.uuid
      sandbox_row = audit_log!(sandbox, production.id, batch_id)
      audit_log!(production, sandbox.id, batch_id)

      after_commit { Admin::SlackNotificationJob.perform_later(sandbox_row.id) }
    end

    def audit_log!(organization, feature_key, batch_id)
      CsAdminAuditLog.create!(
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
