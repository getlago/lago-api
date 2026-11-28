# frozen_string_literal: true

module Roles
  # Makes the sandbox copy of a production custom role match it: created, updated or discarded. The code is the key,
  # as Roles::UpdateService never changes it. A predefined role is shared by every organization and returns itself.
  class SyncSandboxService < BaseService
    Result = BaseResult[:sandbox_role]

    def initialize(role:, actor: nil)
      @role = role
      @actor = actor
      super
    end

    def call
      if role.organization_id.nil?
        result.sandbox_role = role
        return result
      end

      ActiveRecord::Base.transaction do
        sandbox = Organizations::SandboxLockService.call!(organization: role.organization, lock_sandbox: true)
          .sandbox_organization
        next unless sandbox

        copy = sandbox.roles.find_by(code: role.code)
        if role.discarded?
          discard(sandbox, copy) if copy
        else
          result.sandbox_role = copy ? update(sandbox, copy) : create(sandbox)
        end
      end

      result
    end

    private

    attr_reader :role, :actor

    def create(sandbox)
      copy = sandbox.roles.create!(code: role.code, name: role.name, description: role.description,
        permissions: role.permissions)
      log(sandbox, "role.created", role_code: copy.code, permissions: copy.permissions)
      copy
    end

    def update(sandbox, copy)
      copy.update!(name: role.name, description: role.description, permissions: role.permissions)
      log(sandbox, "role.updated", role_code: copy.code) if copy.previous_changes.except("updated_at").any?
      copy
    end

    # The copy's links go with it. A holder who is a member of production is synced again, so they keep production's
    # roles. A sandbox-only holder keeps their other roles, and is revoked only when the copy was their last one.
    def discard(sandbox, copy)
      links = MembershipRole.where(organization: sandbox, role: copy)
      holders = sandbox.memberships.active.where(id: links.select(:membership_id)).includes(:user).order(:user_id).to_a

      deleted_at = Time.current
      links.update_all(deleted_at:, updated_at: deleted_at) # rubocop:disable Rails/SkipsModelValidations
      copy.discard!
      log(sandbox, "role.deleted", role_code: copy.code)

      production_user_ids = role.organization.memberships.active.where(user_id: holders.map(&:user_id)).pluck(:user_id)
      with_roles = MembershipRole.where(membership_id: holders.map(&:id)).distinct.pluck(:membership_id)
      holders.each do |holder|
        next if production_user_ids.exclude?(holder.user_id) && with_roles.include?(holder.id)

        Memberships::SyncSandboxService.call!(organization: role.organization, user: holder.user, actor:)
      end
    end

    def log(sandbox, log_event, resources)
      user = actor || Membership.find_by(id: CurrentContext.membership.to_s.split("/").last)&.user
      after_commit do
        Utils::SecurityLog.produce(organization: sandbox, log_type: "role", log_event:, user:, resources:)
      end
    end
  end
end
