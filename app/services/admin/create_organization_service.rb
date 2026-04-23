# frozen_string_literal: true

module Admin
  class CreateOrganizationService < ::BaseService
    Result = BaseResult[:organization]

    def initialize(actor:, name:, owner_email:, timezone: nil, premium_integrations: [], feature_flags: [], reason:)
      @actor = actor
      @name = name
      @owner_email = owner_email
      @timezone = timezone
      @premium_integrations = premium_integrations || []
      @feature_flags = feature_flags || []
      @reason = reason
      super
    end

    def call
      batch_id = SecureRandom.uuid

      organization = Organizations::CreateService
        .call(name:, document_numbering: "per_organization")
        .raise_if_error!
        .organization

      organization.update!(premium_integrations:) if premium_integrations.any?

      feature_flags.each do |flag|
        organization.enable_feature_flag!(flag)
      end

      Invites::CreateService.call(
        current_organization: organization,
        email: owner_email,
        roles: %w[admin],
        skip_admin_check: true
      )

      create_audit_logs!(organization, batch_id)

      result.organization = organization

      CsAdminAuditLog.where(batch_id:).find_each do |log|
        Admin::SlackNotificationJob.perform_later(log.id)
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :actor, :name, :owner_email, :timezone, :premium_integrations, :feature_flags, :reason

    def create_audit_logs!(organization, batch_id)
      premium_integrations.each do |key|
        CsAdminAuditLog.create!(
          actor_user: actor,
          actor_email: actor.email,
          action: :org_created,
          organization:,
          feature_type: :premium_integration,
          feature_key: key,
          before_value: nil,
          after_value: true,
          reason:,
          batch_id:
        )
      end

      feature_flags.each do |key|
        CsAdminAuditLog.create!(
          actor_user: actor,
          actor_email: actor.email,
          action: :org_created,
          organization:,
          feature_type: :feature_flag,
          feature_key: key,
          before_value: nil,
          after_value: true,
          reason:,
          batch_id:
        )
      end
    end
  end
end
