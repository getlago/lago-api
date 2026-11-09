# frozen_string_literal: true

module Mutations
  module Signups
    class Confirm < BaseMutation
      include RequiresSelfServeSignup
      include GuardsSignupAttempts

      graphql_name "ConfirmSignupEmail"
      description "Confirms a self-serve signup link, creates the user and opens a session"

      input_object_class Types::Signups::ConfirmSignupEmailInput

      type Types::Payloads::LoginUserType

      def resolve(token:, signup_secret: nil, password: nil, captcha_token: nil)
        # The password path runs bcrypt, so it also needs reCAPTCHA.
        guard = password.present? ? :confirm_signup_email_with_password : :confirm_signup_email_with_secret
        guard_error = signup_guard_error(guard, captcha_token:)
        return guard_error if guard_error

        result = ::Signups::ConfirmService.call(token:, signup_secret:, password:)
        result.success? ? result : result_error(result)
      end
    end
  end
end
