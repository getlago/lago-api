# frozen_string_literal: true

module Memberships
  class RevokeService < BaseService
    def call(id)
      membership = Membership.find_by(id: id)
      return result.fail!(code: 'membership_not_found') unless membership

      if result.user.id == membership.user.id
        return result.fail!(
          code: 'unprocessable_entity',
          message: 'Cannot revoke own membership',
        )
      end

      membership.mark_as_revoked!

      result.membership = membership
      result
    end
  end
end
