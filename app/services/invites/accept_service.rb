# frozen_string_literal: true

module Invites
  class AcceptService < BaseService
    Result = BaseResult[:membership, :organization, :token, :user]

    def call(**args)
      invite = args[:invite] || Invite.find_by(token: args[:token], status: :pending)
      return result.not_found_failure!(resource: "invite") unless invite
      unless invite.login_method_allowed?(args[:login_method])
        return result.single_validation_failure!(error_code: "login_method_not_authorized", field: args[:login_method])
      end

      # NOTE: SSO flows skip this check. The identity provider has already checked the email.
      if args[:login_method] == Organizations::AuthenticationMethods::EMAIL_PASSWORD
        existing_user = invite.existing_user

        return join_as_existing_user(invite, existing_user, args) if existing_user
      end

      register_new_user(invite, args)
    end

    private

    def register_new_user(invite, args)
      ActiveRecord::Base.transaction do
        registration_result = UsersService.call(
          :register_from_invite,
          invite,
          args[:password],
          login_method: args[:login_method]
        )
        return result.fail_with_error!(registration_result.error) unless registration_result.success?

        result.user = registration_result.user
        result.organization = registration_result.organization
        result.membership = registration_result.membership
        result.token = generate_token(result.user, login_method: args[:login_method], **args.fetch(:token_claims, {}))
        invite.recipient = result.membership
        invite.mark_as_accepted!
        result
      end

      # Skip log for new users: invite acceptance covers this event
      UserDevices::RegisterService.call!(user: result.user, skip_log: result.user&.previously_new_record?)
      result
    end

    def join_as_existing_user(invite, user, args)
      authentication_result = AuthenticateUserService.call(user:, password: args[:password])
      return result.fail_with_error!(authentication_result.error) unless authentication_result.success?

      join_result = JoinService.call(invite:, user:, login_method: args[:login_method])
      return result.fail_with_error!(join_result.error) unless join_result.success?

      result.user = user
      result.membership = join_result.membership
      result.organization = invite.organization
      result.token = generate_token(user, login_method: args[:login_method], **args.fetch(:token_claims, {}))
      return result unless result.success?

      UserDevices::RegisterService.call!(user:, skip_log: false)
      result
    end

    def generate_token(user, **extra_auth)
      Utils::AuthToken.encode(user:, **extra_auth)
    rescue => e
      result.service_failure!(code: "token_encoding_error", message: e.message)
    end
  end
end
