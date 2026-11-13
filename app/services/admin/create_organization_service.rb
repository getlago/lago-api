# frozen_string_literal: true

module Admin
  class CreateOrganizationService < ::BaseService
    Result = BaseResult[:organization, :sandbox_organization, :invite_url]

    def initialize(actor:, name:, owner_email:, reason:, timezone: nil, premium_integrations: [], feature_flags: [], self_serve: false)
      @actor = actor
      @name = name
      @owner_email = owner_email
      @timezone = timezone
      @premium_integrations = (premium_integrations || []).uniq
      @feature_flags = (feature_flags || []).uniq
      @reason = reason
      @self_serve = self_serve
      super()
    end

    def call
      return result.validation_failure!(errors: {feature_flags: ["invalid"]}) unless valid_feature_flags?

      ActiveRecord::Base.transaction do
        creation = ::Organizations::CreateWithInviteService.call!(
          name:, owner_email:, timezone:, premium_integrations:, feature_flags:, document_numbering: "per_organization",
          self_serve:
        )
        organization = creation.organization
        sandbox = creation.sandbox_organization

        create_audit_logs!(organization, sandbox)

        result.organization = organization
        result.sandbox_organization = sandbox&.reload
        result.invite_url = creation.invite_url
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :actor, :name, :owner_email, :timezone, :premium_integrations, :feature_flags, :reason, :self_serve

    def valid_feature_flags?
      feature_flags.all? { |flag| FeatureFlag.valid?(flag) }
    end

    # The sandbox gets only its creation row: its settings are copies, and a row of their own would let a rollback
    # toggle the sandbox alone.
    def create_audit_logs!(organization, sandbox)
      batch_id = SecureRandom.uuid
      entries = [[organization, "organization", "organization"]]
      entries.concat(premium_integrations.map { |key| [organization, "premium_integration", key] })
      entries.concat(feature_flags.map { |key| [organization, "feature_flag", key] })
      entries << [sandbox, "organization", "organization"] if sandbox

      entries.each do |audited, feature_type, feature_key|
        audit_log = CsAdminAuditLog.create!(
          actor_user: actor,
          actor_email: actor.email,
          action: :org_created,
          organization: audited,
          feature_type:,
          feature_key:,
          before_value: (feature_type == "organization") ? nil : false,
          after_value: true,
          reason:,
          batch_id:
        )

        after_commit { Admin::SlackNotificationJob.perform_later(audit_log.id) }
      end
    end
  end
end
