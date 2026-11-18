# frozen_string_literal: true

module Types
  module Signups
    class ConfirmSignupEmailInput < BaseInputObject
      description "Confirm a self-serve signup link"

      # Nullable, so a missing token answers captcha_failed instead of a schema error (see GuardsSignupAttempts).
      argument :captcha_token, String, required: false
      argument :password, String, required: false, description: "The Step 1 password, when the signup secret of this link's attempt is not known"
      argument :signup_secret, String, required: false
      argument :token, String, required: true
    end
  end
end
