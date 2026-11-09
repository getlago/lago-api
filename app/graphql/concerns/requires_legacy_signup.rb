# frozen_string_literal: true

# Guards the single-screen signup, which skips the email verification, domain policy and captcha of self-serve signup:
# refused once LAGO_SELF_SERVE_ENABLED is on, before its throttle counts the attempt and before any call to Google.
module RequiresLegacySignup
  def ready?(**args)
    raise forbidden_error(code: "legacy_signup_disabled") if Lago::SelfServe.enabled?

    super
  end
end
