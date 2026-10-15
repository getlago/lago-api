# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PasswordResets::Create do
  include_context "with mocked security logger"

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership, organization:) }
  let(:user) { membership.user }
  let(:email) { user.email }
  # A fresh store per example, so the counters do not carry over between examples.
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  let(:mutation) do
    <<~GQL
      mutation($input: CreatePasswordResetInput!) {
        createPasswordReset(input: $input) {
          id
        }
      }
    GQL
  end

  before { Auth::AttemptsThrottle.store = cache }

  def request_reset(email)
    execute_graphql(query: mutation, variables: {input: {email:}})
  end

  context "with a valid user" do
    subject(:result) { request_reset(email) }

    it "enqueues the password reset job and returns an id" do
      expect { result }.to have_enqueued_job(PasswordResets::CreateJob).with(email)

      expect(result["data"]["createPasswordReset"]["id"]).to be_present
    end

    it "creates a password reset once the job runs" do
      expect { perform_enqueued_jobs(only: PasswordResets::CreateJob) { result } }
        .to change(PasswordReset.where(user:), :count).by(1)
    end

    it_behaves_like "produces a security log", "user.password_reset_requested" do
      before { perform_enqueued_jobs(only: PasswordResets::CreateJob) { result } }
    end
  end

  context "with an unknown email" do
    it "returns the same response and does the same work as for a known email" do
      known = request_reset(user.email)

      expect { request_reset("nobody@example.com") }
        .to have_enqueued_job(PasswordResets::CreateJob).with("nobody@example.com")

      unknown = request_reset("nobody@example.com")

      expect(unknown["errors"]).to be_nil
      expect(unknown["data"]["createPasswordReset"]["id"]).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      expect(unknown.to_json.length).to eq(known.to_json.length)
    end

    it "does not create a password reset once the job runs" do
      expect { perform_enqueued_jobs(only: PasswordResets::CreateJob) { request_reset("nobody@example.com") } }
        .not_to change(PasswordReset, :count)
    end
  end

  it "does not return the password reset id" do
    result = perform_enqueued_jobs(only: PasswordResets::CreateJob) { request_reset(email) }

    expect(result["data"]["createPasswordReset"]["id"]).not_to eq(PasswordReset.last.id)
  end

  context "with attempts throttling" do
    it "allows 3 requests per email per hour" do
      expect { 3.times { request_reset(email) } }.to have_enqueued_job(PasswordResets::CreateJob).exactly(3).times

      result = nil
      expect { result = request_reset(email) }.not_to have_enqueued_job(PasswordResets::CreateJob)
      expect(result["errors"].first.dig("extensions", "code")).to eq("too_many_requests")
    end

    context "when the requests come from one client IP" do
      let(:request) { instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10") }

      def request_reset(email)
        execute_graphql(query: mutation, request:, variables: {input: {email:}})
      end

      it "allows 10 requests per hour across emails" do
        expect { 10.times { |i| request_reset("user-#{i}@example.com") } }
          .to have_enqueued_job(PasswordResets::CreateJob).exactly(10).times

        result = nil
        expect { result = request_reset(email) }.not_to have_enqueued_job(PasswordResets::CreateJob)
        expect(result["errors"].first.dig("extensions", "code")).to eq("too_many_requests")
      end
    end
  end
end
