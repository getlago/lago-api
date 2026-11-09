# frozen_string_literal: true

module Auth
  # The rules a Google account logs in by: Google login, and a Google signup of an address that already has a user.
  module GoogleLoginRules
    module_function

    # verify_oidc checks the signature, audience, issuer and expiry, not that Google verified the email.
    def email_verified?(claims)
      ActiveModel::Type::Boolean.new.cast(claims["email_verified"]) == true
    end

    # The validation failure that refuses the login ({error_code:, field:}), or nil when the user may log in.
    def refusal(user, claims)
      needs_organization = user.present? && user.needs_organization? && email_verified?(claims)

      if !user || !(needs_organization || user.memberships.active.any?)
        {error_code: "user_does_not_exist"}
      # A user without an organization has no organization login policy yet.
      elsif !needs_organization && !user.login_method_allowed?(Organizations::AuthenticationMethods::GOOGLE_OAUTH)
        {error_code: "login_method_not_authorized", field: Organizations::AuthenticationMethods::GOOGLE_OAUTH}
      end
    end
  end
end
