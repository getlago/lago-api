# frozen_string_literal: true

module Admin
  class RenameOrganizationService < ::BaseService
    Result = BaseResult[:audit_log]

    MAX_REASON_LENGTH = 500

    def initialize(actor:, organization:, name:, reason:)
      @actor = actor
      @organization = organization
      @name = name.to_s.strip
      @reason = reason.to_s.strip
      super()
    end

    def call
      return result.not_found_failure!(resource: "organization") unless organization
      return result.single_validation_failure!(field: :name, error_code: "value_is_mandatory") if name.blank?
      return result.single_validation_failure!(field: :name, error_code: "value_is_unchanged") if name == organization.name
      return result.single_validation_failure!(field: :reason, error_code: "value_is_too_short") if reason.length < 10
      return result.single_validation_failure!(field: :reason, error_code: "value_is_too_long") if full_reason.length > MAX_REASON_LENGTH

      organization.with_lock do
        audit_log = CsAdminAuditLog.new(
          actor_user: actor,
          actor_email: actor.email,
          action: :org_renamed,
          organization:,
          feature_type: :organization,
          feature_key: "name",
          before_value: nil,
          after_value: true,
          reason: full_reason
        )
        audit_log.validate!

        organization.update!(name:)
        audit_log.save!
        result.audit_log = audit_log

        after_commit { Admin::SlackNotificationJob.perform_later(audit_log.id) }
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :actor, :organization, :name, :reason

    def full_reason
      @full_reason ||= "Renamed from \"#{organization.name}\" to \"#{name}\". #{reason}"
    end
  end
end
