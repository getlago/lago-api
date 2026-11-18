# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Auth::Google::SignUp do
  subject(:result) { sign_up }

  let(:issued) { Auth::GoogleOauthState.issue }
  let(:authorizer) { instance_double(Google::Auth::UserAuthorizer) }
  let(:siteverify) { stub_recaptcha_siteverify(action: Signups::VerifyCaptchaService::SIGNUP_GOOGLE) }
  let(:mutation) do
    <<~GQL
      mutation($input: GoogleSignUpInput!) {
        googleSignUp(input: $input) { token needsOrganization user { email } }
      }
    GQL
  end

  include_context "with self-serve enabled"

  before do
    stub_const("ENV", ENV.to_h.merge("GOOGLE_AUTH_CLIENT_ID" => "client_id", "GOOGLE_AUTH_CLIENT_SECRET" => "client_secret"))
    Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
    allow(Google::Auth::UserAuthorizer).to receive(:new).and_return(authorizer)
    allow(authorizer).to receive(:get_credentials_from_code)
      .and_return(instance_double(Google::Auth::UserRefreshCredentials, id_token: "id_token"))
    allow(Google::Auth::IDTokens).to receive(:verify_oidc)
      .and_return("email" => "jane@getlago.com", "email_verified" => true, "hd" => "getlago.com")
    siteverify
  end

  def sign_up(ip: "203.0.113.10", captcha_token: "captcha-token")
    execute_graphql(
      query: mutation,
      request: instance_double(ActionDispatch::Request, remote_ip: ip),
      variables: {input: {code: "code", state: issued.state, stateSecret: issued.secret, captchaToken: captcha_token}}
    )
  end

  def extensions(response)
    response["errors"].first["extensions"]
  end

  it_behaves_like "a self-serve signup step"

  it "verifies the captcha, then returns a session that needs an organization" do
    expect(result["data"]["googleSignUp"]).to include("needsOrganization" => true, "user" => {"email" => "jane@getlago.com"})
    expect(result["data"]["googleSignUp"]["token"]).to be_present
    expect(siteverify).to have_been_requested.once
  end

  it "refuses a missing captcha before exchanging the code" do
    expect(extensions(sign_up(captcha_token: nil))).to eq("status" => 403, "code" => "captcha_failed")
    expect(authorizer).not_to have_received(:get_credentials_from_code)
  end

  it "refuses a captcha made for another action" do
    stub_recaptcha_siteverify(action: Signups::VerifyCaptchaService::SIGNUP)

    expect(extensions(result)["code"]).to eq("captcha_failed")
  end

  it "shares the signup limit of the network with signUp" do
    10.times { sign_up }

    expect(extensions(sign_up)).to eq("status" => 429, "code" => "too_many_requests")
    expect(sign_up(ip: "198.51.100.7")["errors"]).to be_nil
  end

  it "answers a personal account in details" do
    allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_return("email" => "jane@gmail.com", "email_verified" => true)

    expect(extensions(result)).to include("status" => 422, "details" => {"base" => ["company_google_account_required"]})
  end
end
