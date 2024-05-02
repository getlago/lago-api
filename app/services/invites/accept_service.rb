# frozen_string_literal: true

module Invites
  class AcceptService < BaseService
    def call(**args)
      invite = args[:invite] || Invite.find_by(token: args[:token], status: :pending)
      return result.not_found_failure!(resource: 'invite') unless invite

      ActiveRecord::Base.transaction do
        result = UsersService.new.register_from_invite(invite, args[:password])

        invite.recipient = result.membership

        invite.mark_as_accepted!

        result
      end
    end
  end
end
