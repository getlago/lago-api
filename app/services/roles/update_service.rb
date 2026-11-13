# frozen_string_literal: true

module Roles
  class UpdateService < BaseService
    Result = BaseResult[:role]

    def initialize(role:, acting_membership:, params:)
      @role = role
      @acting_membership = acting_membership
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: "role") unless role
      return result.forbidden_failure!(code: "predefined_role") if predefined_role?

      ActiveRecord::Base.transaction do
        Organizations::SandboxLockService.call!(organization: role.organization)
        # Every role write takes the lock: reloaded, the checks and the logged diff see the last committed edit.
        role.reload
        return result.not_found_failure!(resource: "role") if role.discarded?
        return result.forbidden_failure!(code: "cannot_grant_permissions") unless acting_membership.can_grant_roles?([role])
        return result.forbidden_failure!(code: "cannot_grant_permissions") if adding_permissions_not_held?

        role.update!(params.slice(:name, :description, :permissions).compact)
        Roles::SyncSandboxService.call!(role:, actor: acting_membership.user)

        changes = role.previous_changes
        after_commit { register_security_log(changes) }
      end

      result.role = role
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :role, :acting_membership, :params

    # A member can only update a role they could grant, and only add permissions they hold.
    def adding_permissions_not_held?
      return false if params[:permissions].nil?

      !acting_membership.can_grant_permissions?(params[:permissions] - role.permissions)
    end

    def predefined_role?
      role.organization_id.nil?
    end

    # Takes the changes of the update: the sync reloads nothing, but logs run after commit.
    def register_security_log(changes)
      diff = changes.slice("name", "description").to_h
        .transform_keys(&:to_sym)
        .transform_values { |v| {deleted: v[0], added: v[1]}.compact }

      if changes.key?("permissions")
        old_perms, new_perms = changes["permissions"]
        entry = {}
        deleted = old_perms - new_perms
        added = new_perms - old_perms
        entry[:deleted] = deleted if deleted.present?
        entry[:added] = added if added.present?
        diff[:permissions] = entry if entry.present?
      end

      Utils::SecurityLog.produce(
        organization: role.organization,
        log_type: "role",
        log_event: "role.updated",
        resources: {role_code: role.code, **diff}
      )
    end
  end
end
