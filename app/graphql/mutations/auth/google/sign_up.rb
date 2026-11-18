# frozen_string_literal: true

module Mutations
  module Auth
    module Google
      class SignUp < BaseMutation
        include RequiresSelfServeSignup
        include GuardsSignupAttempts

        graphql_name "GoogleSignUp"
        description "Signs up with a company Google account, or logs in when the account already has a user"

        input_object_class Types::Auth::Google::SignUpInput

        type Types::Payloads::LoginUserType

        def resolve(code:, state:, state_secret:, captcha_token: nil)
          # Before the code exchange and any write.
          guard_error = signup_guard_error(:google_sign_up, captcha_token:)
          return guard_error if guard_error

          result = ::Signups::CreateWithGoogleService.call(code:, state:, state_secret:)
          result.success? ? result : result_error(result)
        end
      end
    end
  end
end
