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
      result = ActiveRecord::Base.transaction do
        result = UsersService.call(:register_from_invite, invite, args[:password])
        result.token = generate_token(result.user, login_method: args[:login_method])
        invite.recipient = result.membership
        invite.mark_as_accepted!
        result
      end

      # Skip log for new users: invite acceptance covers this event
      UserDevices::RegisterService.call!(user: result.user, skip_log: result.user&.previously_new_record?)
      result
    end

    # NOTE: The password is only checked here, never changed. An invitation must not change the
    #       password of an account. A user with no active membership cannot log in, so we ask for
    #       their password instead of an existing session.
    def join_as_existing_user(invite, user, args)
      # NOTE: Whoever created the invitation picks the authentication methods of the inviting
      #       organization. They must not decide how the invited user logs in. A user with no
      #       active membership belongs to no organization, so nothing restricts them.
      if user.memberships.active.any? && !user.login_method_allowed?(args[:login_method])
        return result.single_validation_failure!(
          error_code: "login_method_not_authorized",
          field: args[:login_method]
        )
      end

      unless authenticated?(user, args[:password])
        return result.single_validation_failure!(error_code: "incorrect_login_or_password")
      end

      join_result = JoinService.call(invite:, user:, login_method: args[:login_method])
      return result.fail_with_error!(join_result.error) unless join_result.success?

      result.user = user
      result.membership = join_result.membership
      result.organization = invite.organization
      result.token = generate_token(user, login_method: args[:login_method])
      return result unless result.success?

      UserDevices::RegisterService.call!(user:, skip_log: false)
      result
    end

    def authenticated?(user, password)
      password = password.to_s
      # NOTE: Null byte injection. Prevent 500 errors.
      return false if password.include?("\u0000")

      user.authenticate(password).present?
    end

    def generate_token(user, **extra_auth)
      Utils::AuthToken.encode(user:, **extra_auth)
    rescue => e
      result.service_failure!(code: "token_encoding_error", message: e.message)
    end
  end
end
