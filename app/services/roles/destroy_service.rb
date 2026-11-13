# frozen_string_literal: true

module Roles
  class DestroyService < BaseService
    Result = BaseResult[:role]

    def initialize(role:, actor: nil)
      @role = role
      @actor = actor
      super
    end

    def call
      return result.not_found_failure!(resource: "role") unless role
      return result.forbidden_failure!(code: "predefined_role") if predefined_role?

      ActiveRecord::Base.transaction do
        # Under the lock, so no membership gains the role before it is discarded.
        Organizations::SandboxLockService.call!(organization: role.organization)
        # Reloaded: a role deleted while this waited is gone, and discarding it again would discard its sandbox copy's
        # replacement.
        role.reload
        return result.not_found_failure!(resource: "role") if role.discarded?
        return result.forbidden_failure!(code: "role_assigned_to_members") if role.active_memberships.exists?

        role.discard!
        Roles::SyncSandboxService.call!(role:, actor:)
        after_commit { register_security_log }
      end

      result.role = role
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :role, :actor

    def predefined_role?
      role.organization_id.nil?
    end

    def register_security_log
      Utils::SecurityLog.produce(
        organization: role.organization,
        log_type: "role",
        log_event: "role.deleted",
        resources: {role_code: role.code}
      )
    end
  end
end
