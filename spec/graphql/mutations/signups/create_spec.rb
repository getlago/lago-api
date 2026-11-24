# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Signups::Create do
  subject(:result) { sign_up(email:) }

  let(:email) { "jane@getlago.com" }
  let(:password) { "Lago-Passw0rd" }
  let(:captcha_token) { "captcha-token" }
  let(:remote_ip) { "203.0.113.10" }
  let(:siteverify) { stub_recaptcha_siteverify(action: Signups::VerifyCaptchaService::SIGNUP) }
  let(:mutation) do
    <<~GQL
      mutation($input: SignUpInput!) {
        signUp(input: $input) { signupSecret }
      }
    GQL
  end

  include_context "with self-serve enabled"

  before do
    Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
    siteverify
  end

  def sign_up(email:, ip: remote_ip, token: captcha_token)
    execute_graphql(
      query: mutation,
      request: instance_double(ActionDispatch::Request, remote_ip: ip),
      variables: {input: {email:, password:, captchaToken: token}}
    )
  end

  it_behaves_like "a self-serve signup step"

  context "when signups are paused" do
    let(:self_serve_env) { super().merge("LAGO_DISABLE_SIGNUP" => "true") }

    it "refuses before calling Google" do
      result

      expect(siteverify).not_to have_been_requested
    end
  end

  it "verifies the captcha and returns the signup secret" do
    expect(result["data"]["signUp"]["signupSecret"]).to match(PendingSignup::SECRET_FORMAT)
    expect(siteverify).to have_been_requested.once
    expect(Signups::DeliverVerificationJob).to have_been_enqueued.with(PendingSignup.sole.id)
  end

  it "refuses a missing captcha token with captcha_failed, not a schema error" do
    response = sign_up(email:, token: nil)

    expect(response["errors"].first["extensions"]).to eq("status" => 403, "code" => "captcha_failed")
    expect(PendingSignup.count).to eq(0)
  end

  it "answers an address with an account exactly like a new one, and only the emails differ" do
    create(:user, email: "taken@getlago.com")

    taken = sign_up(email: "taken@getlago.com")
    fresh = sign_up(email: "fresh@getlago.com")

    expect(taken.keys).to eq(fresh.keys)
    expect(taken["data"]["signUp"].keys).to eq(["signupSecret"])
    expect(taken["errors"]).to be_nil

    perform_enqueued_jobs

    subjects = ActionMailer::Base.deliveries.to_h { [it.to.first, it.subject] }
    expect(subjects).to eq(
      "taken@getlago.com" => "You already have a Lago account",
      "fresh@getlago.com" => "Verify your email to finish creating your Lago account"
    )
  end

  it "creates no user or organization" do
    expect { result }.not_to change { [User.count, Organization.count] }
  end

  it "returns the email and password errors in details" do
    response = execute_graphql(
      query: mutation,
      request: instance_double(ActionDispatch::Request, remote_ip:),
      variables: {input: {email: "jane@gmail.com", password: "lago", captchaToken: captcha_token}}
    )

    expect(response["errors"].first["extensions"]).to include(
      "status" => 422,
      "code" => "unprocessable_entity",
      "details" => {
        "email" => ["email_domain_not_allowed"],
        "password" => %w[password_too_short password_missing_uppercase password_missing_number password_missing_special_character]
      }
    )
  end

  it "limits signups per network" do
    10.times { sign_up(email: "jane#{it}@getlago.com") }

    expect(sign_up(email: "jane@getlago.com")["errors"].first["extensions"])
      .to eq("status" => 429, "code" => "too_many_requests")
  end

  it "limits emails per mailbox, +tags included" do
    sign_up(email: "jane@getlago.com")

    expect(sign_up(email: "jane+1@getlago.com", ip: "198.51.100.7")["errors"].first["extensions"])
      .to eq("status" => 429, "code" => "too_many_requests")
  end
end
