# frozen_string_literal: true

module Mutations
  module PasswordResets
    class Reset < BaseMutation
      include ThrottlesAuthAttempts

      graphql_name "ResetPassword"
      description "Reset password for user and log in"

      argument :new_password, String, required: true
      argument :token, String, required: true

      type Types::Payloads::LoginUserType

      def resolve(new_password:, token:)
        return too_many_attempts_error if ::Auth::AttemptsThrottle.hit!(:credentials_per_ip, client_ip)

        result = ::PasswordResets::ResetService.call(token:, new_password:)

        result.success? ? result : result_error(result)
      end
    end
  end
end
