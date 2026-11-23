# frozen_string_literal: true

module Invites
  class RevokeService < BaseService
    Result = BaseResult[:invite]

    def initialize(invite)
      @invite = invite
      super
    end

    def call
      return result.not_found_failure!(resource: "invite") unless invite

      revoked = ActiveRecord::Base.transaction do
        # An acceptance that held the lock may have committed since the caller loaded the invite.
        invite.lock!
        next false unless invite.pending?

        invite.mark_as_revoked!
      end
      return result.not_found_failure!(resource: "invite") unless revoked

      result.invite = invite
      result
    end

    private

    attr_reader :invite
  end
end
