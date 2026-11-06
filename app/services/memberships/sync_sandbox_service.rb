# frozen_string_literal: true

module Memberships
  # Makes a user's sandbox membership match their membership of the production organization: created, roles changed,
  # or revoked. State based, so the same call follows any change and running it twice changes nothing.
  #
  # It skips the sandbox's own guards on purpose: production already enforced self revoke, last admin and grants, and
  # the MembershipRole discard guards would otherwise leave access on a sandbox that drifted.
  class SyncSandboxService < BaseService
    Result = BaseResult[:sandbox_membership]

    def initialize(organization:, user:, actor: nil)
      @organization = organization
      @user = user
      @actor = actor
      super
    end

    def call
      return result unless organization.production?

      ActiveRecord::Base.transaction do
        sandbox = Organizations::SandboxLockService.call!(organization:, lock_sandbox: true).sandbox_organization
        next unless sandbox

        source = organization.memberships.active.find_by(user_id: user.id)
        target = sandbox.memberships.active.find_by(user_id: user.id)

        if source.nil?
          revoke(sandbox, target) if target
        elsif target.nil?
          add(sandbox, source)
        else
          sync_roles(sandbox, source, target)
        end
      end

      result
    end

    private

    attr_reader :organization, :user, :actor

    def revoke(sandbox, target)
      target.mark_as_revoked!
      log(sandbox, "user.deleted", email: user.email)
    end

    def add(sandbox, source)
      membership = Membership.create!(user:, organization: sandbox)
      roles = sandbox_roles(source)
      roles.each { MembershipRole.create!(organization: sandbox, membership:, role: it) }

      result.sandbox_membership = membership
      log(sandbox, "user.added", email: user.email, roles: roles.map(&:code))
    end

    def sync_roles(sandbox, source, target)
      wanted = sandbox_roles(source)
      current = target.roles.to_a
      added = wanted - current
      deleted = current - wanted

      added.each { MembershipRole.create!(organization: sandbox, membership: target, role: it) }
      if deleted.any?
        MembershipRole.where(membership: target, role: deleted).update_all(deleted_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end

      result.sandbox_membership = target
      return if added.empty? && deleted.empty?

      roles = {added: added.map(&:code), deleted: deleted.map(&:code)}.reject { |_, codes| codes.empty? }
      log(sandbox, "user.role_edited", email: user.email, roles:)
    end

    # A predefined role is the same row in both organizations; a custom role has its own copy in the sandbox.
    def sandbox_roles(source)
      source.roles.map do |role|
        role.organization_id.nil? ? role : Roles::SyncSandboxService.call!(role:, actor:).sandbox_role
      end.compact
    end

    def log(sandbox, log_event, resources)
      user = actor_user
      after_commit do
        Utils::SecurityLog.produce(organization: sandbox, log_type: "user", log_event:, user:, resources:)
      end
    end

    # The production actor: SecurityLog alone would look their membership up in the sandbox and find none.
    def actor_user
      actor || Membership.find_by(id: CurrentContext.membership.to_s.split("/").last)&.user
    end
  end
end
