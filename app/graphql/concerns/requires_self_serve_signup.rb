# frozen_string_literal: true

# Guards the self-serve steps that send signup email or create a user or an organization: self-serve first, then the
# LAGO_DISABLE_SIGNUP kill switch, so a self-hosted deployment never answers signup_disabled.
module RequiresSelfServeSignup
  include RequiresSelfServe

  private

  def ensure_self_serve_available!
    super
    raise forbidden_error(code: "signup_disabled") if Lago::SelfServe.signup_disabled?
  end
end
