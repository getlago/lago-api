# frozen_string_literal: true

module Memberships
  class RevokeService < BaseService
    Result = BaseResult[:membership]

    def initialize(user:, membership:)
      @user = user
      @membership = membership

      super
    end

    def call
      return result.not_found_failure!(resource: "membership") unless membership

      ActiveRecord::Base.transaction do
        # Under the lock, so the last admin check holds until the revoke commits.
        Organizations::SandboxLockService.call!(organization: membership.organization)
        return result.forbidden_failure!(code: "cannot_revoke_own_membership") if user.id == membership.user.id
        return result.not_allowed_failure!(code: "last_admin") if membership.admin? && membership.organization.admin_membership_roles.count == 1

        membership.mark_as_revoked!
        # A failure here rolls the revoke back: it never commits while the sandbox keeps access.
        Memberships::SyncSandboxService.call!(organization: membership.organization, user: membership.user, actor: user)
        after_commit { register_security_log }
      end

      result.membership = membership
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :user, :membership

    def register_security_log
      Utils::SecurityLog.produce(
        organization: membership.organization,
        log_type: "user",
        log_event: "user.deleted",
        user: user,
        resources: {email: membership.user.email}
      )
    end
  end
end
