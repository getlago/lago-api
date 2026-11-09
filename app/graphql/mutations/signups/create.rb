# frozen_string_literal: true

module Mutations
  module Signups
    class Create < BaseMutation
      include RequiresSelfServeSignup
      include GuardsSignupAttempts

      graphql_name "SignUp"
      description "Starts a self-serve signup: emails a verification link and returns the secret that proves this browser started it"

      argument :email, String, required: true
      argument :password, String, required: true
      captcha_token_argument

      field :signup_secret, String, null: false

      def resolve(email:, password:, captcha_token: nil)
        guard_error = signup_guard_error(:sign_up, captcha_token:)
        return guard_error if guard_error

        result = ::Signups::CreateService.call(email:, password:)

        if result.success?
          {signup_secret: result.signup_secret}
        elsif result.error.is_a?(BaseService::MethodNotAllowedFailure) && result.error.code == "too_many_requests"
          too_many_attempts_error
        else
          result_error(result)
        end
      end
    end
  end
end
