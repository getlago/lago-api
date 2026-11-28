# frozen_string_literal: true

module Admin
  # Opens a pending self-serve production organization for a CS admin, when the card path cannot (billing-accounts
  # down, or a prospect opened without a card), with an audit row and one Slack notification.
  class ActivateOrganizationService < ::BaseService
    Result = BaseResult[:organization]

    def initialize(actor:, organization:, reason:)
      @actor = actor
      @organization = organization
      @reason = reason
      super()
    end

    def call
      return result.not_found_failure!(resource: "organization") unless organization

      # Checked before the activation, as the row is written after it.
      audit_log.validate!

      ActiveRecord::Base.transaction do
        activation = ::Organizations::ActivateService.call!(organization:, actor:, reason:)

        # An organization that was already open is left as it is, without a row.
        if activation.activated
          audit_log.save!
          after_commit { Admin::SlackNotificationJob.perform_later(audit_log.id) }
        end

        result.organization = activation.organization
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :actor, :organization, :reason

    def audit_log
      @audit_log ||= CsAdminAuditLog.new(
        actor_user: actor,
        actor_email: actor.email,
        action: :organization_activated,
        organization:,
        feature_type: :organization,
        feature_key: organization.id,
        before_value: false,
        after_value: true,
        reason:
      )
    end
  end
end
