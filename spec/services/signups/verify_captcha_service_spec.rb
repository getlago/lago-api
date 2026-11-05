# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::VerifyCaptchaService do
  subject(:result) { described_class.call(token:, action:, remote_ip:) }

  let(:token) { "captcha-token" }
  let(:action) { described_class::SIGNUP }
  let(:remote_ip) { "203.0.113.10" }
  let(:siteverify) { stub_recaptcha_siteverify(action:, score:, **siteverify_answer) }
  let(:score) { 0.9 }
  let(:siteverify_answer) { {} }

  before { siteverify }

  def expect_refused
    expect(result.error).to be_a(BaseService::ForbiddenFailure)
    expect(result.error.code).to eq("captcha_failed")
  end

  def expect_unavailable
    expect(result.error).to be_a(BaseService::ServiceFailure)
    expect(result.error.code).to eq("captcha_unavailable")
  end

  context "with a token Google accepts" do
    it "returns the score and sends the secret, token and IP in the form body only" do
      expect(result).to be_success
      expect(result.score).to eq(0.9)
      expect(
        a_request(:post, described_class::SITEVERIFY_URL)
          .with(body: {secret: "recaptcha-test-secret", response: token, remoteip: remote_ip})
      ).to have_been_made.once
      expect(a_request(:post, /siteverify\?/)).not_to have_been_made
    end

    it "accepts every action when Google answers that action" do
      described_class::ACTIONS.each do |action|
        stub_recaptcha_siteverify(action:)

        expect(described_class.call(token:, action:)).to be_success
      end
    end

    context "without a client IP" do
      let(:remote_ip) { nil }

      it "omits remoteip" do
        result

        expect(a_request(:post, described_class::SITEVERIFY_URL).with(body: {secret: "recaptcha-test-secret", response: token}))
          .to have_been_made.once
      end
    end
  end

  context "with an action outside the constants" do
    it "raises" do
      expect { described_class.call(token:, action: "login") }.to raise_error(ArgumentError)
    end
  end

  context "with a missing, blank or oversized token" do
    it "refuses without calling Google" do
      [nil, "", "a" * 4_097].each do |token|
        expect(described_class.call(token:, action:).error.code).to eq("captcha_failed")
      end

      expect(siteverify).not_to have_been_requested
    end
  end

  context "when Google rejects the token" do
    let(:siteverify_answer) { {success: false} }

    it "refuses for a token verdict or no error code" do
      [["invalid-input-response"], ["timeout-or-duplicate"], []].each do |error_codes|
        stub_recaptcha_siteverify(action:, success: false, error_codes:)

        expect(described_class.call(token:, action:).error.code).to eq("captcha_failed")
      end
    end

    it "is unavailable and reports when our secret or request is at fault", :sentry do
      [["invalid-input-secret"], ["bad-request"], ["something-new"]].each do |error_codes|
        stub_recaptcha_siteverify(action:, success: false, error_codes:)

        expect(described_class.call(token:, action:).error.code).to eq("captcha_unavailable")
      end

      expect(sentry_events.map(&:message)).to eq(["reCAPTCHA verification unavailable"] * 3)
    end
  end

  context "when Google answers without an action, as for a v2 key", :sentry do
    before do
      stub_recaptcha_siteverify(action:)
      stub_request(:post, described_class::SITEVERIFY_URL).to_return(
        status: 200,
        body: {success: true, hostname: URI(Rails.application.config.lago_front_url).host}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
      Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
    end

    it "refuses and warns once per window" do
      codes = Array.new(2) { described_class.call(token:, action:).error.code }

      expect(codes).to eq(%w[captcha_failed captcha_failed])
      expect(sentry_events.map { [it.message, it.level, it.extra[:reason]] })
        .to eq([["reCAPTCHA answer suggests a key misconfiguration", :warning, "missing_action"]])
    end
  end

  context "when the token was made for another action" do
    let(:siteverify) { stub_recaptcha_siteverify(action: described_class::SIGNUP_RESEND) }

    it "refuses" do
      expect_refused
    end
  end

  context "when the token was made on another site", :sentry do
    let(:siteverify_answer) { {hostname: "evil.example.com"} }

    it "refuses and warns with both hostnames" do
      expect_refused
      expect(sentry_events.last.message).to eq("reCAPTCHA hostname differs from LAGO_FRONT_URL")
      expect(sentry_events.last.level).to eq(:warning)
      expect(sentry_events.last.extra).to include(hostname: "evil.example.com", expected_hostname: URI(Rails.application.config.lago_front_url).host)
    end
  end

  context "when the hostname differs only by case" do
    let(:siteverify_answer) { {hostname: URI(Rails.application.config.lago_front_url).host.upcase} }

    it "accepts the token" do
      expect(result).to be_success
    end
  end

  describe "score threshold" do
    it "refuses below 0.5 and accepts 0.5" do
      stub_recaptcha_siteverify(action:, score: 0.4)
      expect(described_class.call(token:, action:).error.code).to eq("captcha_failed")

      stub_recaptcha_siteverify(action:, score: 0.5)
      expect(described_class.call(token:, action:)).to be_success
    end

    it "refuses a missing or non-numeric score" do
      [nil, "0.9"].each do |score|
        stub_recaptcha_siteverify(action:, score:)

        expect(described_class.call(token:, action:).error.code).to eq("captcha_failed")
      end
    end

    context "with LAGO_RECAPTCHA_MIN_SCORE set" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_RECAPTCHA_MIN_SCORE" => "0.7")) }

      let(:score) { 0.6 }

      it "applies it" do
        expect_refused
      end
    end

    context "with an empty LAGO_RECAPTCHA_MIN_SCORE" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_RECAPTCHA_MIN_SCORE" => "")) }

      it "applies the default" do
        expect(result).to be_success
      end
    end

    context "with a malformed LAGO_RECAPTCHA_MIN_SCORE" do
      it "is unavailable without calling Google" do
        %w[high 1.5 -0.1].each do |value|
          stub_const("ENV", ENV.to_h.merge("LAGO_RECAPTCHA_MIN_SCORE" => value))

          expect(described_class.call(token:, action:).error.code).to eq("captcha_unavailable")
        end

        expect(siteverify).not_to have_been_requested
      end
    end
  end

  context "without LAGO_RECAPTCHA_SECRET_KEY", :sentry do
    before { stub_const("ENV", ENV.to_h.except("LAGO_RECAPTCHA_SECRET_KEY")) }

    it "is unavailable, calls nothing and reports" do
      expect_unavailable
      expect(siteverify).not_to have_been_requested
      expect(sentry_events.last.level).to eq(:error)
    end

    context "with the throttling store up" do
      before { Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new }

      it "reports once per window, however many signups it refuses" do
        3.times { described_class.call(token:, action:) }

        expect(sentry_events.size).to eq(1)
      end
    end
  end

  context "when Google fails" do
    it "is unavailable for an error status, a timeout, a refused connection or an unexpected body" do
      [
        -> { it.to_return(status: 500, body: "") },
        -> { it.to_timeout },
        -> { it.to_raise(Errno::ECONNREFUSED) },
        -> { it.to_return(status: 200, body: "<html>") },
        -> { it.to_return(status: 200, body: "[]") }
      ].each do |answer|
        answer.call(stub_request(:post, described_class::SITEVERIFY_URL))

        expect(described_class.call(token:, action:).error.code).to eq("captcha_unavailable")
      end
    end
  end

  describe "logging" do
    let(:score) { 0.3 }

    it "logs the outcome, reason and score without the token or the IP" do
      allow(Rails.logger).to receive(:info).and_call_original

      result

      expect(Rails.logger).to have_received(:info)
        .with("Signups::VerifyCaptchaService action=signup outcome=refused reason=low_score score=0.3")
    end

    context "with a token Google rejects" do
      let(:siteverify_answer) { {success: false, error_codes: ["invalid-input-response"]} }

      before { allow(Rails.logger).to receive(:info).and_call_original }

      it "logs Google's codes" do
        result

        expect(Rails.logger).to have_received(:info)
          .with("Signups::VerifyCaptchaService action=signup outcome=refused reason=rejected:invalid-input-response score=")
      end
    end
  end
end
