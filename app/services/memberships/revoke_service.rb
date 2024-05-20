# frozen_string_literal: true

module Memberships
  class RevokeService < BaseService
    def call(id)
      membership = Membership.find_by(id:)
      return result.not_found_failure!(resource: 'membership') unless membership
      return result.not_allowed_failure!(code: 'cannot_revoke_own_membership') if result.user.id == membership.user.id
      return result.not_allowed_failure!(code: 'last_admin') if membership.organization.memberships.admin.count == 1 && membership.admin?

      membership.mark_as_revoked!

      result.membership = membership
      result
    end
  end
end
