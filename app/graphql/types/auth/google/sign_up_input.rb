# frozen_string_literal: true

module Types
  module Auth
    module Google
      class SignUpInput < Types::BaseInputObject
        graphql_name "GoogleSignUpInput"
        description "Sign up for self-serve Lago with a company Google account"

        # Nullable, so a missing token answers captcha_failed instead of a schema error (see GuardsSignupAttempts).
        argument :captcha_token, String, required: false
        argument :code, String, required: true
        argument :state, String, required: true
        argument :state_secret, String, required: true, description: "The secret googleAuthUrl returned to this tab"
      end
    end
  end
end
