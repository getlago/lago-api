# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::AgentStorefront::Create, :premium do
  include_context "with mocked security logger"

  let(:required_permission) { "organization:integrations:create" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:stripe_provider) { create(:stripe_provider, organization:, code: "stripe_spt_prod", name: "Stripe SPT Prod") }
  let(:plan) { create(:plan, organization:, code: "count_per_call", name: "Count per call", amount_cents: 0, amount_currency: "USD") }
  let(:premium_integrations) { %w[agent_storefront events_targeting_wallets] }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateAgentStorefrontIntegrationInput!) {
        createAgentStorefrontIntegration(input: $input) {
          id
          code
          name
          paymentProviderCode
          paymentProvider { id code name sellerProfile }
          resourceEndpoint
          resourceInstructions
          scope
          agentUrl
          authDocumentUrl
          billingDocumentUrl
          claimUrl
          plans { planCode minimumTopupCents maximumTopupCents freeCreditsCents plan { id code name amountCurrency } }
          hasEnrolledAgents
          hasAgentsWithStripeCustomer
        }
      }
    GQL
  end

  let(:input) do
    {
      code: "agentic_flow_a",
      name: "Agentic Flow A",
      paymentProviderCode: stripe_provider.code,
      resourceEndpoint: "https://api.acme.example/v1/count",
      resourceInstructions: "https://api.acme.example/COUNT.md",
      plans: [{planCode: plan.code, minimumTopupCents: 500, maximumTopupCents: 10_000, freeCreditsCents: 1000}]
    }
  end

  let(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  before do
    stripe_provider
    organization.update!(premium_integrations:, feature_flags: %w[agent_storefront])
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LAGO_REDIS_CACHE_URL").and_return("redis://redis:6379")
    allow(ENV).to receive(:[]).with("LAGO_DISABLE_WALLET_REFRESH").and_return(nil)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:create"

  context "with valid input" do
    it "creates the storefront with the plans it sells" do
      expect { result }.to change(Integrations::AgentStorefrontIntegration, :count).by(1)

      storefront = organization.agent_storefront_integrations.sole
      data = result["data"]["createAgentStorefrontIntegration"]

      expect(data).to eq(
        "id" => storefront.id,
        "code" => "agentic_flow_a",
        "name" => "Agentic Flow A",
        "paymentProviderCode" => "stripe_spt_prod",
        "paymentProvider" => {"id" => stripe_provider.id, "code" => "stripe_spt_prod", "name" => "Stripe SPT Prod", "sellerProfile" => nil},
        "resourceEndpoint" => "https://api.acme.example/v1/count",
        "resourceInstructions" => "https://api.acme.example/COUNT.md",
        "scope" => "agentic_flow_a:use",
        "agentUrl" => "#{ENV["LAGO_API_URL"]}/agents/v1/#{storefront.id}",
        "authDocumentUrl" => "#{ENV["LAGO_API_URL"]}/agents/v1/#{storefront.id}/AUTH.md",
        "billingDocumentUrl" => "#{ENV["LAGO_API_URL"]}/agents/v1/#{storefront.id}/BILLING.md",
        "claimUrl" => "#{Rails.application.config.lago_front_url}/agent-claim/#{storefront.id}",
        "plans" => [
          {
            "planCode" => "count_per_call",
            "minimumTopupCents" => "500",
            "maximumTopupCents" => "10000",
            "freeCreditsCents" => "1000",
            "plan" => {"id" => plan.id, "code" => "count_per_call", "name" => "Count per call", "amountCurrency" => "USD"}
          }
        ],
        "hasEnrolledAgents" => false,
        "hasAgentsWithStripeCustomer" => false
      )
    end

    it_behaves_like "produces a security log", "integration.created" do
      before { result }
    end
  end

  context "without the plans" do
    let(:input) { super().except(:plans) }

    it "creates the storefront with no plan sold" do
      expect(result["data"]["createAgentStorefrontIntegration"]["plans"]).to eq([])
    end
  end

  context "when the code is already used" do
    before { create(:agent_storefront_integration, organization:, code: "agentic_flow_a") }

    it "returns a validation error on the code" do
      expect_graphql_error(result:, message: "Unprocessable Entity")
      expect(result["errors"].first["extensions"]["details"]).to eq("code" => ["value_already_exist"])
    end
  end

  context "when a URL is not https" do
    let(:input) { super().merge(resourceEndpoint: "http://api.acme.example/v1/count", resourceInstructions: "acme.example/COUNT.md") }

    it "returns a validation error on each URL" do
      expect(result["errors"].first["extensions"]["details"]).to eq(
        "resourceEndpoint" => ["url_is_invalid"],
        "resourceInstructions" => ["url_is_invalid"]
      )
    end
  end

  context "when the payment connection does not exist" do
    let(:input) { super().merge(paymentProviderCode: "unknown") }

    it "returns a validation error on the payment connection" do
      expect(result["errors"].first["extensions"]["details"]).to eq("paymentProviderCode" => ["payment_provider_not_found"])
    end
  end

  context "when a sold plan has a subscription fee" do
    let(:plan) { create(:plan, organization:, amount_cents: 100) }

    it "returns a validation error on the plans" do
      expect(result["errors"].first["extensions"]["details"]).to eq("plans" => ["plan_not_usage_only"])
    end
  end

  context "when the organization lacks the agent storefront premium integration" do
    let(:premium_integrations) { %w[events_targeting_wallets] }

    it "returns a not allowed error" do
      expect_graphql_error(result:, message: "premium_integration_missing")
    end
  end

  context "when the organization lacks wallet-targeted events" do
    let(:premium_integrations) { %w[agent_storefront] }

    it "returns a validation error" do
      expect(result["errors"].first["extensions"]["details"]).to eq("base" => ["events_targeting_wallets_disabled"])
    end
  end
end
