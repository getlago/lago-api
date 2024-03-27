# frozen_string_literal: true

module Invites
  class RevokeService < BaseService
    def call(**args)
      invite = args[:current_organization].invites.pending.find_by(id: args[:id], status: :pending)
      return result.not_found_failure!(resource: "invite") unless invite

      invite.mark_as_revoked!

      result.invite = invite
      result
    end
  end
end
