# frozen_string_literal: true

module Signups
  # Verifies a reCAPTCHA v3 token with Google. Fails closed: any doubt refuses, including a Google outage or a
  # missing secret, and every token verdict gives the same answer, so the API is not a scoring oracle.
  class VerifyCaptchaService < BaseService
    SIGNUP = "signup"
    SIGNUP_GOOGLE = "signup_google"
    SIGNUP_RESEND = "signup_resend"
    SIGNUP_CONFIRM = "signup_confirm"
    ACTIONS = [SIGNUP, SIGNUP_GOOGLE, SIGNUP_RESEND, SIGNUP_CONFIRM].freeze

    SITEVERIFY_URL = "https://www.google.com/recaptcha/api/siteverify"
    DEFAULT_MIN_SCORE = 0.5
    MAX_TOKEN_LENGTH = 4_096
    # Verdicts on the token itself (bot, replay, expired page), as opposed to our secret or request.
    TOKEN_ERROR_CODES = %w[missing-input-response invalid-input-response timeout-or-duplicate].freeze
    NETWORK_ERRORS = [IOError, OpenSSL::SSL::SSLError, SocketError, SystemCallError, Timeout::Error].freeze

    Result = BaseResult[:score]

    def initialize(token:, action:, remote_ip: nil)
      @token = token
      @action = action
      @remote_ip = remote_ip
      super
    end

    def call
      raise ArgumentError, "unknown reCAPTCHA action #{action.inspect}" unless ACTIONS.include?(action)
      return refuse!("missing_token") if token.blank? || token.length > MAX_TOKEN_LENGTH
      return unavailable!("missing_secret") if secret_key.blank?
      return unavailable!("invalid_min_score") unless min_score

      response = siteverify
      return unavailable!("unexpected_response") unless response.is_a?(Hash)
      return token_rejected!(response["error-codes"]) unless response["success"] == true
      return refuse!("wrong_action") unless response["action"] == action
      return wrong_hostname!(response["hostname"]) unless response["hostname"].to_s.downcase == expected_hostname

      score = response["score"]
      return refuse!("low_score", score:) unless score.is_a?(Numeric) && score >= min_score

      log("passed", score:)
      result.score = score
      result
    rescue LagoHttpClient::HttpError, JSON::ParserError, *NETWORK_ERRORS => e
      unavailable!(e.class.name)
    end

    private

    attr_reader :token, :action, :remote_ip

    def secret_key
      ENV["LAGO_RECAPTCHA_SECRET_KEY"]
    end

    # A malformed value never lowers the bar: it refuses every token instead.
    def min_score
      value = Float(ENV["LAGO_RECAPTCHA_MIN_SCORE"].presence || DEFAULT_MIN_SCORE, exception: false)
      value if value && (0.0..1.0).cover?(value)
    end

    def expected_hostname
      URI(Rails.application.config.lago_front_url).host.to_s.downcase
    end

    # Short timeouts and no retry: a slow Google must not hold one of the few Puma threads.
    # The secret goes in the form body, never in the URL, which HttpError#message includes.
    def siteverify
      LagoHttpClient::Client.new(SITEVERIFY_URL, open_timeout: 2, write_timeout: 2, read_timeout: 3)
        .post_url_encoded({secret: secret_key, response: token, remoteip: remote_ip.presence}.compact, {})
    end

    def token_rejected!(error_codes)
      if Array(error_codes).all? { TOKEN_ERROR_CODES.include?(it) }
        refuse!("rejected")
      else
        unavailable!("google_error")
      end
    end

    # Google enforces the key's domains, so a mismatch nearly always means this region's LAGO_FRONT_URL is wrong.
    def wrong_hostname!(hostname)
      if Auth::AttemptsThrottle.first_in_period?("captcha_wrong_hostname", 10.minutes)
        Sentry.capture_message(
          "reCAPTCHA hostname differs from LAGO_FRONT_URL",
          level: :warning,
          extra: {action:, expected_hostname:, hostname:}
        )
      end
      refuse!("wrong_hostname")
    end

    def refuse!(reason, score: nil)
      log("refused", reason:, score:)
      result.forbidden_failure!(code: "captcha_failed")
    end

    def unavailable!(reason)
      log("unavailable", reason:)
      # Every signup fails while this lasts: one report per reason and window, the log keeps each occurrence.
      if Auth::AttemptsThrottle.first_in_period?("captcha_unavailable:#{reason}", 10.minutes)
        Sentry.capture_message("reCAPTCHA verification unavailable", level: :error, extra: {reason:, action:})
      end
      result.service_failure!(code: "captcha_unavailable", message: reason)
    end

    # Never logs the token, the IP or the secret.
    def log(outcome, reason: nil, score: nil)
      Rails.logger.info("#{self.class.name} action=#{action} outcome=#{outcome} reason=#{reason} score=#{score}")
    end
  end
end
