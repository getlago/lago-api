# frozen_string_literal: true

module Mutations
  module Signups
    class ExchangeSecret < BaseMutation
      include RequiresSelfServe
      include GuardsSignupAttempts

      graphql_name "ExchangeSignupSecret"
      description "Opens a session in the tab that started a self-serve signup, once its email is confirmed"

      argument :signup_secret, String, required: true

      type Types::Payloads::LoginUserType

      def resolve(signup_secret:)
        guard_error = signup_guard_error(:exchange_signup_secret)
        return guard_error if guard_error

        result = ::Signups::ExchangeSecretService.call(signup_secret:)
        result.success? ? result : result_error(result)
      end
    end
  end
end
