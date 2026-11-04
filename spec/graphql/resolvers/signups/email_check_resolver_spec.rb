# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Signups::EmailCheckResolver do
  subject(:result) { check(email) }

  let(:email) { "jane@getlago.com" }
  let(:query) do
    <<~GQL
      query($email: String!) {
        signupEmailCheck(email: $email) { valid code }
      }
    GQL
  end

  include_context "with self-serve enabled"

  before { Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new }

  def check(email)
    execute_graphql(query:, request: instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10"), variables: {email:})
  end

  it_behaves_like "a self-serve entry point"

  it "answers with the server's checks, without creating anything" do
    answers = ["jane@getlago.com", "", "jane@", "jane@gmail.com"].index_with { check(it)["data"]["signupEmailCheck"] }

    expect(answers).to eq(
      "jane@getlago.com" => {"valid" => true, "code" => nil},
      "" => {"valid" => false, "code" => "value_is_mandatory"},
      "jane@" => {"valid" => false, "code" => "invalid_email_format"},
      "jane@gmail.com" => {"valid" => false, "code" => "email_domain_not_allowed"}
    )
    expect(PendingSignup.count).to eq(0)
  end

  it "gives the same answer for an address with an account" do
    create(:user, email: "jane@getlago.com")

    expect(result["data"]["signupEmailCheck"]).to eq("valid" => true, "code" => nil)
  end

  it "limits checks per network" do
    60.times { check(email) }

    expect(result["errors"].first["extensions"]).to eq("status" => 429, "code" => "too_many_requests")
  end
end
