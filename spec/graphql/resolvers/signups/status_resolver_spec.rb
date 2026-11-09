# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Signups::StatusResolver do
  subject(:result) { poll(signup_secret) }

  let(:signup_secret) { PendingSignup.generate_signup_secret }
  let(:query) do
    <<~GQL
      query($signupSecret: String!) {
        signupStatus(signupSecret: $signupSecret) { status }
      }
    GQL
  end

  include_context "with self-serve enabled"

  before do
    Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
    create(:pending_signup, signup_secret:)
  end

  def poll(signup_secret)
    execute_graphql(query:, request: instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10"), variables: {signupSecret: signup_secret})
  end

  it_behaves_like "a self-serve entry point"

  it "answers pending, then verified once confirmed" do
    expect(result["data"]["signupStatus"]).to eq("status" => "pending")

    PendingSignup.sole.update!(verified_at: Time.current, user: create(:user), password_digest: nil)

    expect(poll(signup_secret)["data"]["signupStatus"]).to eq("status" => "verified")
  end

  it "answers expired after 48 hours, and invalid for an unknown secret" do
    expect(poll(PendingSignup.generate_signup_secret)["data"]["signupStatus"]).to eq("status" => "invalid")

    travel_to(50.hours.from_now) { expect(result["data"]["signupStatus"]).to eq("status" => "expired") }
  end

  it "limits polling per network" do
    60.times { poll(signup_secret) }

    expect(result["errors"].first["extensions"]).to eq("status" => 429, "code" => "too_many_requests")
  end
end
