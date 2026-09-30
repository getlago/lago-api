# frozen_string_literal: true

module Admin
  class ToggleFeatureService < ::BaseService
    Result = BaseResult[:audit_log]

    def initialize(actor:, organization:, feature_type:, feature_key:, enabled:, reason:, notify_org_admin:)
      @actor = actor
      @organization = organization
      @feature_type = feature_type
      @feature_key = feature_key
      @enabled = enabled
      @reason = reason
      @notify_org_admin = notify_org_admin
      super()
    end

    def call
      result.audit_log = ApplyFeatureChangeService.call!(
        actor:, organization:, feature_type:, feature_key:, enabled:, reason:, notify_org_admin:
      ).audit_log

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :actor, :organization, :feature_type, :feature_key, :enabled, :reason, :notify_org_admin
  end
end
