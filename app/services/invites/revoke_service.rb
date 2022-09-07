# frozen_string_literal: true

module Invites
  class RevokeService < BaseService
    def call(id)
      invite = Invite.find_by(id: id, status: :pending)
      return result.fail!(code: 'invite_not_found') unless invite

      invite.mark_as_revoked!

      result.invite = invite
      result
    end
  end
end
