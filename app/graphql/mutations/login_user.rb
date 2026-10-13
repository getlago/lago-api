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
      if ::Auth::AttemptsThrottle.hit!(:login_per_ip, client_ip) ||
          ::Auth::AttemptsThrottle.exceeded?(:login_failures_per_email, email)
        return too_many_attempts_error
      end

      result = UsersService.call(:login, email, password)

      if result.success?
        ::Auth::AttemptsThrottle.reset!(:login_failures_per_email, email)
        result
      else
        ::Auth::AttemptsThrottle.hit!(:login_failures_per_email, email)
        result_error(result)
      end
    end
  end
end
