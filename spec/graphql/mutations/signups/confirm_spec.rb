# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Signups::Confirm do
  subject(:result) { confirm(signupSecret: signup_secret) }

  let(:signup_secret) { PendingSignup.generate_signup_secret }
  let(:pending_signup) { create(:pending_signup, email: "jane@getlago.com", signup_secret:, password: "Signup-Passw0rd") }
  let(:token) { PendingSignupToken.generate }
  let(:mutation) do
    <<~GQL
      mutation($input: ConfirmSignupEmailInput!) {
        confirmSignupEmail(input: $input) { token user { email organizations { id } } }
      }
    GQL
  end

  include_context "with self-serve enabled"

  before do
    Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
    create(:pending_signup_token, pending_signup:, token:)
  end

  def confirm(**input)
    execute_graphql(
      query: mutation,
      request: instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10"),
      variables: {input: {token:, **input}}
    )
  end

  def extensions(response)
    response["errors"].first["extensions"]
  end

  it_behaves_like "a self-serve signup step"

  it "creates the user and returns a session with no organization" do
    expect(result["data"]["confirmSignupEmail"]["token"]).to be_present
    expect(result["data"]["confirmSignupEmail"]["user"]).to eq("email" => "jane@getlago.com", "organizations" => [])
  end

  context "when signups are paused" do
    let(:self_serve_env) { super().merge("LAGO_DISABLE_SIGNUP" => "true") }

    it "creates no user" do
      expect { result }.not_to change(User, :count)
    end
  end

  context "with the Step 1 password on another device" do
    let(:siteverify) { stub_recaptcha_siteverify(action: Signups::VerifyCaptchaService::SIGNUP_CONFIRM) }

    before { siteverify }

    it "verifies the captcha, then creates the user" do
      response = confirm(password: "Signup-Passw0rd", captchaToken: "captcha-token")

      expect(response["data"]["confirmSignupEmail"]["user"]["email"]).to eq("jane@getlago.com")
      expect(siteverify).to have_been_requested.once
    end

    it "refuses a missing captcha before checking the password" do
      expect(extensions(confirm(password: "Signup-Passw0rd"))).to eq("status" => 403, "code" => "captcha_failed")
      expect(User.count).to eq(0)
    end

    it "answers each password refusal in details" do
      expect(extensions(confirm(password: "Wrong-Passw0rd", captchaToken: "captcha-token"))).to include(
        "status" => 422, "code" => "unprocessable_entity", "details" => {"password" => ["incorrect_password"]}
      )
    end
  end

  it "asks for the password without the attempt's secret" do
    expect(extensions(confirm)).to include("status" => 422, "details" => {"password" => ["password_required"]})
  end

  it "answers each link refusal" do
    confirm(signupSecret: signup_secret)
    expect(extensions(confirm(signupSecret: signup_secret))).to eq("status" => 405, "code" => "email_already_verified")

    unknown = execute_graphql(
      query: mutation,
      request: instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10"),
      variables: {input: {token: "broken", signupSecret: signup_secret}}
    )
    expect(extensions(unknown)).to eq("status" => 404, "code" => "not_found", "details" => {"signupToken" => ["not_found"]})
  end

  it "answers signup_token_locked after 5 password tries" do
    PendingSignupToken.update_all(failed_password_attempts: 5) # rubocop:disable Rails/SkipsModelValidations

    expect(extensions(confirm)).to eq("status" => 405, "code" => "signup_token_locked")
  end

  it "limits confirms per network" do
    20.times { confirm(signupSecret: PendingSignup.generate_signup_secret) }

    expect(extensions(result)).to eq("status" => 429, "code" => "too_many_requests")
  end
end
