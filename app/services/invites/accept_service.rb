# frozen_string_literal: true

module Invites
  class AcceptService < BaseService
    def call(**args)
      invite = args[:invite] || Invite.find_by(token: args[:token], status: :pending)
      return result.not_found_failure!(resource: "invite") unless invite
      unless invite.organization.authentication_methods.include?(args[:login_method])
        return result.single_validation_failure!(error_code: "login_method_not_authorized", field: args[:login_method])
      end

      ActiveRecord::Base.transaction do
        result = UsersService.new.register_from_invite(invite, args[:password])

        result.token = generate_token(result.user, login_method: args[:login_method])
        invite.recipient = result.membership

        invite.mark_as_accepted!

        result
      end
    end

    private

    def generate_token(user, **extra_auth)
      Auth::TokenService.encode(user:, **extra_auth)
    rescue => e
      result.service_failure!(code: "token_encoding_error", message: e.message)
    end
  end
end
