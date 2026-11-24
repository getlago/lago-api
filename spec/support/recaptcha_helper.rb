# frozen_string_literal: true

module RecaptchaHelper
  # Sets the reCAPTCHA secret and stubs Google's siteverify answer for the given action. Returns the WebMock stub.
  def stub_recaptcha_siteverify(action:, score: 0.9, success: true, error_codes: [], secret_key: "recaptcha-test-secret",
    hostname: URI(Rails.application.config.lago_front_url).host)
    unless Signups::VerifyCaptchaService::ACTIONS.include?(action)
      raise ArgumentError, "use a Signups::VerifyCaptchaService action constant, got #{action.inspect}"
    end

    stub_const("ENV", ENV.to_h.merge("LAGO_RECAPTCHA_SECRET_KEY" => secret_key))

    body = {success:, score:, action:, hostname:, challenge_ts: Time.current.iso8601, "error-codes": error_codes}
    stub_request(:post, Signups::VerifyCaptchaService::SITEVERIFY_URL)
      .to_return(status: 200, body: body.to_json, headers: {"Content-Type" => "application/json"})
  end
end
