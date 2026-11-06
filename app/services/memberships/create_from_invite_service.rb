# frozen_string_literal: true

module Memberships
  class CreateFromInviteService < ::BaseService
    Result = BaseResult[:membership]

    def initialize(invite:, user:)
      @invite = invite
      @user = user

      super
    end

    # NOTE: Callers rescue ActiveRecord::RecordInvalid and BaseService::FailedResult. They run this service in their
    #       own transaction, which the locks below hold until it ends.
    def call
      # Refuses a sandbox, including one linked while this acceptance waited for the lock.
      Organizations::SandboxLockService.call!(organization: invite.organization)
      # A revoke or another acceptance committed while it waited leaves the invite no longer pending.
      invite.lock!
      return result.not_found_failure!(resource: "invite") unless invite.pending?

      result.membership = Membership.create!(user:, organization: invite.organization)

      invite.roles.each do |role_code|
        role = Role.with_code(role_code).with_organization(invite.organization_id).first!

        MembershipRole.create!(
          organization: invite.organization,
          membership: result.membership,
          role:
        )
      end

      Memberships::SyncSandboxService.call!(organization: invite.organization, user:, actor: user)
      result
    end

    private

    attr_reader :invite, :user
  end
end
