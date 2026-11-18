# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Signups::StatusResolver do
  subject(:result) { poll(signup_secret) }

  let(:signup_secret) { PendingSignup.generate_signup_secret }
  let(:signup_traits) { [] }
  let(:signup_attributes) { {} }
  let(:query) do
    <<~GQL
      query($signupSecret: String!) {
        signupStatus(signupSecret: $signupSecret) { status resendAvailableInSeconds resendLimitReached }
      }
    GQL
  end

  include_context "with self-serve enabled"

  # Frozen before the attempt is created, so its send times have no sub-seconds.
  before do
    freeze_time
    Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
    create(:pending_signup, *signup_traits, signup_secret:, **signup_attributes)
  end

  def poll(signup_secret)
    execute_graphql(query:, request: instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10"), variables: {signupSecret: signup_secret})
  end

  it_behaves_like "a self-serve entry point"

  it "answers pending" do
    expect(result["data"]["signupStatus"]["status"]).to eq("pending")
  end

  context "with a confirmed signup" do
    let(:signup_traits) { [:verified] }

    it "answers verified, with no resend" do
      expect(result["data"]["signupStatus"]).to eq("status" => "verified", "resendAvailableInSeconds" => nil, "resendLimitReached" => false)
    end
  end

  it "answers expired after 48 hours, and invalid for an unknown secret" do
    expect(poll(PendingSignup.generate_signup_secret)["data"]["signupStatus"])
      .to eq("status" => "invalid", "resendAvailableInSeconds" => nil, "resendLimitReached" => false)

    travel_to(50.hours.from_now) { expect(result["data"]["signupStatus"]["status"]).to eq("expired") }
  end

  context "with a send 20 seconds ago" do
    let(:signup_attributes) { {emails_sent_at: [20.seconds.ago]} }

    it "restores the resend countdown" do
      expect(result["data"]["signupStatus"]).to eq("status" => "pending", "resendAvailableInSeconds" => 40, "resendLimitReached" => false)
    end
  end

  context "with the attempt's 3 emails sent" do
    let(:signup_attributes) { {emails_sent_at: [3.minutes.ago] * 3} }

    it "restores the resend limit" do
      expect(result["data"]["signupStatus"]).to eq("status" => "pending", "resendAvailableInSeconds" => nil, "resendLimitReached" => true)
    end
  end

  context "when the poll asks for the status alone" do
    let(:query) do
      <<~GQL
        query($signupSecret: String!) { signupStatus(signupSecret: $signupSecret) { status } }
      GQL
    end

    it "runs no mailbox query" do
      statements = []
      collect = ->(*, payload) { statements << payload[:sql] }

      ActiveSupport::Notifications.subscribed(collect, "sql.active_record") do
        expect(result["data"]["signupStatus"]).to eq("status" => "pending")
      end
      expect(statements.grep(/WHERE .*mailbox_key/)).to be_empty
    end
  end

  it "limits polling per network" do
    60.times { poll(signup_secret) }

    expect(result["errors"].first["extensions"]).to eq("status" => 429, "code" => "too_many_requests")
  end
end
