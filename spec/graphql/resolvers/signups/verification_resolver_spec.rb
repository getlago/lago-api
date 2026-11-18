# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Signups::VerificationResolver do
  subject(:result) { verify(token:) }

  let(:signup_secret) { PendingSignup.generate_signup_secret }
  let(:pending_signup) { create(:pending_signup, email: "jane@getlago.com", signup_secret:) }
  let(:token) { PendingSignupToken.generate }
  let!(:token_record) { create(:pending_signup_token, pending_signup:, token:) }
  let(:query) do
    <<~GQL
      query($token: String!, $signupSecret: String) {
        signupVerification(token: $token, signupSecret: $signupSecret) { status email passwordRequired }
      }
    GQL
  end

  include_context "with self-serve enabled"

  before { Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new }

  def verify(**variables)
    execute_graphql(query:, request: instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10"), variables:)
  end

  it_behaves_like "a self-serve entry point"

  it "reads a valid link twice without confirming it" do
    2.times do
      expect(result["data"]["signupVerification"]).to eq("status" => "valid", "email" => "jane@getlago.com", "passwordRequired" => true)
    end
    expect(User.count).to eq(0)
  end

  it "does not ask for the password with the attempt's secret" do
    expect(verify(token:, signupSecret: signup_secret)["data"]["signupVerification"]["passwordRequired"]).to be(false)
  end

  it "answers each state, with the email only when valid" do
    token_record.update!(failed_password_attempts: 5)

    expect(result["data"]["signupVerification"]).to eq("status" => "locked", "email" => nil, "passwordRequired" => true)
    expect(verify(token: "broken")["data"]["signupVerification"]["status"]).to eq("invalid")
  end

  it "limits lookups per network" do
    30.times { verify(token: PendingSignupToken.generate) }

    expect(result["errors"].first["extensions"]).to eq("status" => 429, "code" => "too_many_requests")
  end
end
