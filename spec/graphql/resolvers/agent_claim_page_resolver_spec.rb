# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::AgentClaimPageResolver do
  let(:query) do
    <<~GQL
      query($storefrontId: ID!) {
        agentClaimPage(storefrontId: $storefrontId) {
          storefrontName
          organizationName
        }
      }
    GQL
  end
  let(:result) { execute_graphql(query:, variables: {storefrontId: storefront.id}) }

  let_it_be(:organization) { create(:organization, name: "Acme Inc", premium_integrations: %w[agent_storefront], feature_flags: %w[agent_storefront]) }
  let_it_be(:storefront) { create(:agent_storefront_integration, organization:, name: "Agentic Flow A") }

  context "with a premium license", :premium do
    it "returns the names without a session" do
      expect(result["data"]["agentClaimPage"]).to eq("storefrontName" => "Agentic Flow A", "organizationName" => "Acme Inc")
    end

    context "with an unknown storefront" do
      let(:result) { execute_graphql(query:, variables: {storefrontId: SecureRandom.uuid}) }

      it "returns a not found error" do
        expect_not_found(result)
        expect(result["data"]["agentClaimPage"]).to be_nil
      end
    end
  end

  context "without a premium license" do
    it "returns a not found error" do
      expect_not_found(result)
    end
  end
end
