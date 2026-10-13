# frozen_string_literal: true

# Mutations::LoginUser Mutation
module Mutations
  class LoginUser < BaseMutation
    include ThrottlesAuthAttempts

    description "Opens a session for an existing user"

    argument :email, String, required: true
    argument :password, String, required: true

    type Types::Payloads::LoginUserType

    def resolve(email:, password:)
      # The attempt is counted before the password check, so concurrent requests cannot all pass
      # under the limit. A successful login clears the email counter.
      over_ip_limit = ::Auth::AttemptsThrottle.hit!(:login_per_ip, client_ip)
      over_email_limit = ::Auth::AttemptsThrottle.hit!(:login_attempts_per_email, email)
      return too_many_attempts_error if over_ip_limit || over_email_limit

      result = UsersService.call(:login, email, password)
      return result_error(result) unless result.success?

      ::Auth::AttemptsThrottle.reset!(:login_attempts_per_email, email)
      result
    end
  end
end
