# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Signups::Resend do
  subject(:result) { resend(signupSecret: signup_secret) }

  let(:signup_secret) { PendingSignup.generate_signup_secret }
  let(:emails_sent_at) { [2.minutes.ago] }
  let(:expires_at) { 22.hours.from_now }
  let(:pending_signup) { create(:pending_signup, email: "jane@getlago.com", signup_secret:, emails_sent_at:, expires_at:) }
  let(:token) { PendingSignupToken.generate }
  let(:siteverify) { stub_recaptcha_siteverify(action: Signups::VerifyCaptchaService::SIGNUP_RESEND) }
  let(:mutation) do
    <<~GQL
      mutation($input: ResendSignupEmailInput!) {
        resendSignupEmail(input: $input) { resendAvailableInSeconds resendLimitReached }
      }
    GQL
  end

  include_context "with self-serve enabled"

  before do
    freeze_time
    Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
    create(:pending_signup_token, pending_signup:, token:)
    siteverify
  end

  def resend(**input)
    execute_graphql(
      query: mutation,
      request: instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10"),
      variables: {input: {captchaToken: "captcha-token", **input}}
    )
  end

  def extensions(response)
    response["errors"].first["extensions"]
  end

  it_behaves_like "a self-serve signup step"

  context "when signups are paused" do
    let(:self_serve_env) { super().merge("LAGO_DISABLE_SIGNUP" => "true") }

    it "does not call Google" do
      result

      expect(siteverify).not_to have_been_requested
    end
  end

  it "verifies the captcha and answers the countdown" do
    expect(result["data"]["resendSignupEmail"]).to eq("resendAvailableInSeconds" => 60, "resendLimitReached" => false)
    expect(siteverify).to have_been_requested.once
  end

  it "refuses a low score without sending" do
    stub_recaptcha_siteverify(action: Signups::VerifyCaptchaService::SIGNUP_RESEND, score: 0.1)

    expect(extensions(result)).to eq("status" => 403, "code" => "captcha_failed")
    expect(Signups::DeliverVerificationJob).not_to have_been_enqueued
  end

  context "with the attempt's second email sent" do
    let(:emails_sent_at) { [10.minutes.ago, 5.minutes.ago] }

    it "answers the third email with the limit reached" do
      expect(result["data"]["resendSignupEmail"]).to eq("resendAvailableInSeconds" => nil, "resendLimitReached" => true)
    end
  end

  context "when the last email is under a minute old" do
    let(:emails_sent_at) { [20.seconds.ago] }

    it "answers 429 with the seconds left" do
      expect(extensions(result)).to eq("status" => 429, "code" => "resend_too_soon", "details" => {"retryAfterSeconds" => 40})
    end
  end

  context "with 3 emails to the mailbox in the hour" do
    let(:emails_sent_at) { [50.minutes.ago] }

    before { create(:pending_signup, email: "jane+x@getlago.com", emails_sent_at: [40.minutes.ago, 30.minutes.ago]) }

    it "answers 429 until the oldest leaves the hour" do
      expect(extensions(result)).to eq("status" => 429, "code" => "resend_limit_reached", "details" => {"retryAfterSeconds" => 600})
    end
  end

  context "with the attempt's 3 emails sent" do
    let(:emails_sent_at) { [3.hours.ago] * 3 }

    it "answers 405 signup_resend_exhausted" do
      expect(extensions(result)).to eq("status" => 405, "code" => "signup_resend_exhausted")
    end
  end

  context "when 24 hours have passed since Step 1" do
    let(:emails_sent_at) { [3.hours.ago] }
    let(:expires_at) { Time.current }

    it "answers 405 signup_expired" do
      expect(extensions(result)).to eq("status" => 405, "code" => "signup_expired")
    end
  end

  it "stops the previous link" do
    resend(token:)
    perform_enqueued_jobs

    confirm = Signups::ConfirmService.call(token:, signup_secret:)
    expect(confirm.error.code).to eq("signup_token_replaced")
  end

  it "limits resends per network" do
    10.times { resend(signupSecret: PendingSignup.generate_signup_secret) }

    expect(extensions(result)).to eq("status" => 429, "code" => "too_many_requests")
  end
end
