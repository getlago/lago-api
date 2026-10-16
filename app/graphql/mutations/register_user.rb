# frozen_string_literal: true

module Mutations
  class RegisterUser < BaseMutation
    include ThrottlesAuthAttempts

    description "Registers a new user and creates related organization"

    argument :email, String, required: true
    argument :organization_name, String, required: true
    argument :password, String, required: true

    type Types::Payloads::RegisterUserType

    def resolve(email:, password:, organization_name:)
      return too_many_attempts_error if ::Auth::AttemptsThrottle.hit!(:credentials_per_ip, client_ip)

      result = UsersService.call(
        :register,
        email,
        password,
        organization_name
      )

      result.success? ? result : result_error(result)
    end
  end
end
