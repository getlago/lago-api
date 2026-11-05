# frozen_string_literal: true

# Public self-serve signup endpoints call signup_guard_error right after the self-serve gate, before any other work.
# GUARDS holds each endpoint's rules, narrowest first, and reCAPTCHA action, so endpoints declare none of their own.
module GuardsSignupAttempts
  extend ActiveSupport::Concern
  include ThrottlesAuthAttempts

  Guard = Data.define(:captcha_action, :rules)

  # Counted for each token that will reach Google, once the business limits pass, to bound those calls.
  CAPTCHA_RULES = %i[signup_captcha_per_ip signup_captcha_per_ip_block].freeze
  SIGNUP_RULES = %i[signup_per_ip signup_per_ip_daily signup_per_ip_block].freeze

  GUARDS = {
    sign_up: Guard.new(captcha_action: Signups::VerifyCaptchaService::SIGNUP, rules: SIGNUP_RULES),
    google_sign_up: Guard.new(captcha_action: Signups::VerifyCaptchaService::SIGNUP_GOOGLE, rules: SIGNUP_RULES),
    resend_signup_email: Guard.new(
      captcha_action: Signups::VerifyCaptchaService::SIGNUP_RESEND,
      rules: %i[signup_resend_per_ip signup_resend_per_ip_block]
    ),
    # The password path runs bcrypt; the link also counts its own failed passwords in the database.
    confirm_signup_email_with_password: Guard.new(
      captcha_action: Signups::VerifyCaptchaService::SIGNUP_CONFIRM,
      rules: %i[signup_confirm_per_ip]
    ),
    # The lookups below need a 256-bit link token or signup secret, so a captcha would add nothing.
    confirm_signup_email_with_secret: Guard.new(
      captcha_action: nil,
      rules: %i[signup_confirm_per_ip signup_lookup_per_ip_block]
    ),
    signup_verification: Guard.new(captcha_action: nil, rules: %i[signup_verification_per_ip signup_lookup_per_ip_block]),
    signup_status: Guard.new(captcha_action: nil, rules: %i[signup_status_per_ip signup_lookup_per_ip_block]),
    exchange_signup_secret: Guard.new(captcha_action: nil, rules: %i[signup_exchange_per_ip signup_lookup_per_ip_block]),
    signup_email_check: Guard.new(captcha_action: nil, rules: %i[signup_email_check_per_ip signup_lookup_per_ip_block])
  }.freeze

  class_methods do
    # Nullable, so a missing token (reCAPTCHA script blocked) answers captcha_failed instead of a schema error.
    def captcha_token_argument
      argument :captcha_token, String, required: false
    end
  end

  private

  # nil when the request may go on, otherwise the GraphQL error to return. Business limits are counted only once
  # reCAPTCHA passes, so tokens Google refuses never use them up.
  def signup_guard_error(endpoint, captcha_token: nil)
    guard = GUARDS.fetch(endpoint)
    error = signup_captcha_error(guard, captcha_token) if guard.captcha_action
    error || (too_many_attempts_error if signup_rules_over_limit?(guard.rules))
  end

  # A network already at a business limit stops before Google, and only tokens Google will see count against the budget
  # that bounds those calls.
  def signup_captcha_error(guard, captcha_token)
    return too_many_attempts_error if signup_rules_at_limit?(guard.rules)
    if Signups::VerifyCaptchaService.sendable?(captcha_token) && signup_rules_over_limit?(CAPTCHA_RULES)
      return too_many_attempts_error
    end

    captcha = Signups::VerifyCaptchaService.call(token: captcha_token, action: guard.captcha_action, remote_ip: client_ip)
    result_error(captcha) unless captcha.success?
  end

  def signup_rules_at_limit?(rules)
    rule = rules.find { Auth::AttemptsThrottle.at_limit?(it, client_ip) }
    report_signup_limit(rule) if rule
    rule.present?
  end

  # Stops at the first rule over its limit, so a refused attempt never uses up a wider budget (its /48, its day). Each
  # counter increments before its check, so concurrent requests cannot all pass under a limit.
  def signup_rules_over_limit?(rules)
    rule = rules.find { Auth::AttemptsThrottle.hit!(it, client_ip) }
    report_signup_limit(rule) if rule
    rule.present?
  end

  # Never logs the IP. A trip from a trusted proxy address usually means the proxy in front of the API forwards no client
  # address, so every client shares one counter. A public proxy missing from LAGO_TRUSTED_PROXIES never shows here.
  def report_signup_limit(rule)
    trusted = trusted_proxy_ip?
    Rails.logger.warn("#{GuardsSignupAttempts.name} limit reached rule=#{rule} trusted_ip=#{trusted}")

    if trusted && Auth::AttemptsThrottle.first_in_period?("signup_trusted_proxy", 10.minutes)
      Sentry.capture_message("Signup attempts limit reached from a trusted proxy address", level: :warning, extra: {rule:})
    end
  end

  def trusted_proxy_ip?
    ip = IPAddr.new(client_ip.to_s)
    proxies = Rails.application.config.action_dispatch.trusted_proxies || ActionDispatch::RemoteIp::TRUSTED_PROXIES
    proxies.any? { it.include?(ip) }
  rescue IPAddr::Error
    false
  end
end
