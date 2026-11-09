# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Signups::ExchangeSecret do
  subject(:result) { exchange(signup_secret) }

  let(:signup_secret) { PendingSignup.generate_signup_secret }
  let(:pending_signup) { create(:pending_signup, email: "jane@getlago.com", signup_secret:) }
  let(:token) { PendingSignupToken.generate }
  let(:mutation) do
    <<~GQL
      mutation($input: ExchangeSignupSecretInput!) {
        exchangeSignupSecret(input: $input) { token user { email } }
      }
    GQL
  end

  include_context "with self-serve enabled"

  before do
    Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
    create(:pending_signup_token, pending_signup:, token:)
  end

  def exchange(signup_secret)
    execute_graphql(
      query: mutation,
      request: instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10"),
      variables: {input: {signupSecret: signup_secret}}
    )
  end

  def extensions(response)
    response["errors"].first["extensions"]
  end

  it_behaves_like "a self-serve entry point"

  it "opens a session once the link is confirmed, once" do
    Signups::ConfirmService.call!(token:, signup_secret:)

    expect(result["data"]["exchangeSignupSecret"]["user"]).to eq("email" => "jane@getlago.com")
    expect(extensions(exchange(signup_secret))).to eq("status" => 405, "code" => "signup_secret_expired")
  end

  it "answers email_not_verified before the confirmation, and not_found for an unknown secret" do
    expect(extensions(result)).to eq("status" => 405, "code" => "email_not_verified")
    expect(extensions(exchange(PendingSignup.generate_signup_secret)))
      .to eq("status" => 404, "code" => "not_found", "details" => {"signupSecret" => ["not_found"]})
  end

  it "limits exchanges per network" do
    20.times { exchange(PendingSignup.generate_signup_secret) }

    expect(extensions(result)).to eq("status" => 429, "code" => "too_many_requests")
  end
end
