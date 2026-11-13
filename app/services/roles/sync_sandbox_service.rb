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

    # The copy's links go with it, then each sandbox member who held it is synced again, so they keep production's roles.
    def discard(sandbox, copy)
      links = MembershipRole.where(organization: sandbox, role: copy)
      users = User.where(id: sandbox.memberships.active.where(id: links.select(:membership_id)).select(:user_id)).order(:id).to_a

      links.update_all(deleted_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      copy.discard!
      log(sandbox, "role.deleted", role_code: copy.code)

      users.each { Memberships::SyncSandboxService.call!(organization: role.organization, user: it, actor:) }
    end

    def log(sandbox, log_event, resources)
      user = actor || Membership.find_by(id: CurrentContext.membership.to_s.split("/").last)&.user
      after_commit do
        Utils::SecurityLog.produce(organization: sandbox, log_type: "role", log_event:, user:, resources:)
      end
    end
  end
end
