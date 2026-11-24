# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::AgentClaims::Verify, :premium do
  let(:mutation) do
    <<~GQL
      mutation($input: VerifyAgentClaimInput!) {
        verifyAgentClaim(input: $input) {
          status
          claimedAt
        }
      }
    GQL
  end
  let(:input) { {storefrontId: storefront.id, claimCode: "abcd-2345", verificationCode: "123456"} }
  let(:request) { instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10") }
  let(:result) { execute_graphql(query: mutation, request:, variables: {input:}) }

  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront], feature_flags: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:registration) { create(:agent_registration, storefront:) }
  let(:customer) { create(:customer, organization:, external_id: Agents::ExternalIds.customer(registration), email: nil) }
  let(:verification_expires_at) { 10.minutes.from_now }
  let(:claim) do
    create(:agent_claim, :started, registration:, code: "ABCD2345", verification_code_hash: Agents::Claim.digest("123456"), verification_expires_at:)
  end

  before do
    customer
    claim
    Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
  end

  it "claims the agent and gives its customer the owner's e-mail" do
    freeze_time do
      expect(result["data"]["verifyAgentClaim"]).to eq("status" => "claimed", "claimedAt" => Time.current.iso8601)
    end

    expect(claim.reload).to be_verified
    expect(customer.reload.email).to eq("owner@example.com")
  end

  context "with a wrong verification code" do
    let(:input) { {storefrontId: storefront.id, claimCode: "ABCD-2345", verificationCode: "000000"} }

    it "returns the REST error code on the field" do
      expect_unprocessable_entity(result, details: {verificationCode: ["invalid_verification_code"]})
      expect(claim.reload).to be_started
    end
  end

  context "with an expired verification code" do
    let(:verification_expires_at) { 1.minute.ago }

    it "returns the REST error code on the field" do
      expect_unprocessable_entity(result, details: {verificationCode: ["verification_expired"]})
    end
  end

  context "with an unknown storefront" do
    let(:input) { {storefrontId: SecureRandom.uuid, claimCode: "ABCD-2345", verificationCode: "123456"} }

    it "returns a not found error" do
      expect_not_found(result)
    end
  end

  it "takes five verifications per claim code, then refuses" do
    5.times do
      input = {storefrontId: storefront.id, claimCode: "ABCD-2345", verificationCode: "000000"}
      expect_unprocessable_entity(execute_graphql(query: mutation, request:, variables: {input:}), details: {verificationCode: ["invalid_verification_code"]})
    end

    expect(result["errors"].first["extensions"]).to include("status" => 429, "code" => "too_many_requests")
    expect(claim.reload).to be_started
  end
end
