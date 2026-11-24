# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::AgentClaims::Start, :premium do
  let(:mutation) do
    <<~GQL
      mutation($input: StartAgentClaimInput!) {
        startAgentClaim(input: $input) {
          status
          expiresIn
        }
      }
    GQL
  end
  let(:input) { {storefrontId: storefront.id, claimCode: "abcd-2345", email: "owner@example.com"} }
  let(:request) { instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10") }
  let(:result) { execute_graphql(query: mutation, request:, variables: {input:}) }

  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront], feature_flags: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:claim) { create(:agent_claim, registration: enrolled_registration, code: "ABCD2345") }

  before do
    claim
    Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
  end

  def enrolled_registration
    create(:agent_registration, storefront:).tap { create(:customer, organization:, external_id: Agents::ExternalIds.customer(it)) }
  end

  it "mails a verification code to the owner without a session" do
    expect { result }.to have_enqueued_mail(Agents::ClaimMailer, :verification)

    expect(result["data"]["startAgentClaim"]).to eq("status" => "pending", "expiresIn" => 600)
    expect(claim.reload).to be_started
  end

  context "with an unknown claim code" do
    let(:input) { {storefrontId: storefront.id, claimCode: "ZZZZ-2345", email: "owner@example.com"} }

    it "returns the REST error code on the field" do
      expect_unprocessable_entity(result, details: {claimCode: ["invalid_claim_code"]})
    end
  end

  context "with a malformed e-mail" do
    let(:input) { {storefrontId: storefront.id, claimCode: "ABCD-2345", email: "owner"} }

    it "returns the REST error code on the field" do
      expect_unprocessable_entity(result, details: {email: ["invalid_email_format"]})
    end
  end

  context "with an unknown storefront" do
    let(:input) { {storefrontId: SecureRandom.uuid, claimCode: "ABCD-2345", email: "owner@example.com"} }

    it "returns a not found error" do
      expect_not_found(result)
    end
  end

  it "mails a code three times per claim code, then refuses" do
    3.times do |i|
      input = {storefrontId: storefront.id, claimCode: "ABCD-2345", email: "owner#{i}@example.com"}
      expect(execute_graphql(query: mutation, request:, variables: {input:})["data"]["startAgentClaim"]["status"]).to eq("pending")
    end

    expect_graphql_error(result: result, message: "Too Many Requests")
    expect(result["errors"].first["extensions"]).to include("status" => 429, "code" => "too_many_requests")
  end

  it "mails three codes per hour to one mailbox, then refuses" do
    3.times do |i|
      create(:agent_claim, registration: enrolled_registration, code: "CODE234#{i + 2}")
      input = {storefrontId: storefront.id, claimCode: "CODE-234#{i + 2}", email: "owner+#{i}@example.com"}
      expect(execute_graphql(query: mutation, request:, variables: {input:})["data"]["startAgentClaim"]["status"]).to eq("pending")
    end

    expect(result["errors"].first["extensions"]).to include("status" => 429, "code" => "too_many_requests")
    expect(claim.reload).to be_issued
  end
end
