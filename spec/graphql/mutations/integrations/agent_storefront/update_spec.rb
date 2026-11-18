# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::AgentStorefront::Update, :premium do
  include_context "with mocked security logger"

  let(:required_permission) { "organization:integrations:update" }
  let(:mutation) do
    <<-GQL
      mutation($input: UpdateAgentStorefrontIntegrationInput!) {
        updateAgentStorefrontIntegration(input: $input) {
          id
          code
          name
          paymentProviderCode
          resourceEndpoint
          plans { planCode minimumTopupCents maximumTopupCents freeCreditsCents plan { code } }
          hasEnrolledAgents
          hasAgentsWithStripeCustomer
        }
      }
    GQL
  end
  let(:input) { {id: integration.id, name: "Agentic Flow A renamed", resourceEndpoint: "https://api.acme.example/v1/count"} }
  let(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end
  let(:integration) { create(:agent_storefront_integration, organization:, code: "agentic_flow_a", name: "Agentic Flow A") }
  let(:plan) { create(:plan, organization:, code: "count_per_call", name: "Count per call", amount_cents: 0, amount_currency: "USD") }
  let(:other_plan) { create(:plan, organization:, code: "count_bulk", name: "Count bulk", amount_cents: 0, amount_currency: "USD") }

  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let_it_be(:membership, refind: true) { create_default(:membership) }

  before do
    integration.update!(plans: [{plan_code: plan.code, minimum_topup_cents: 500, maximum_topup_cents: 10_000, free_credits_cents: 1000}])
    organization.update!(premium_integrations: %w[agent_storefront events_targeting_wallets], feature_flags: %w[agent_storefront])
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  context "with valid input" do
    it "updates the storefront and keeps the plans it sells" do
      expect(result["data"]["updateAgentStorefrontIntegration"]).to eq(
        "id" => integration.id,
        "code" => "agentic_flow_a",
        "name" => "Agentic Flow A renamed",
        "paymentProviderCode" => integration.payment_provider_code,
        "resourceEndpoint" => "https://api.acme.example/v1/count",
        "plans" => [{"planCode" => "count_per_call", "minimumTopupCents" => "500", "maximumTopupCents" => "10000", "freeCreditsCents" => "1000", "plan" => {"code" => "count_per_call"}}],
        "hasEnrolledAgents" => false,
        "hasAgentsWithStripeCustomer" => false
      )
    end

    it_behaves_like "produces a security log", "integration.updated" do
      before { result }
    end
  end

  context "when the plans are sent" do
    let(:input) { {id: integration.id, plans:} }

    context "with a plan added and the sold one edited" do
      let(:plans) do
        [
          {planCode: plan.code, minimumTopupCents: 1000, maximumTopupCents: 20_000},
          {planCode: other_plan.code, minimumTopupCents: 2000, maximumTopupCents: 50_000, freeCreditsCents: 0}
        ]
      end

      it "replaces the list" do
        expect(result["data"]["updateAgentStorefrontIntegration"]["plans"]).to eq([
          {"planCode" => "count_per_call", "minimumTopupCents" => "1000", "maximumTopupCents" => "20000", "freeCreditsCents" => nil, "plan" => {"code" => "count_per_call"}},
          {"planCode" => "count_bulk", "minimumTopupCents" => "2000", "maximumTopupCents" => "50000", "freeCreditsCents" => "0", "plan" => {"code" => "count_bulk"}}
        ])
      end
    end

    context "with the sold plan left out" do
      let(:plans) { [] }

      it "stops selling it" do
        expect(result["data"]["updateAgentStorefrontIntegration"]["plans"]).to eq([])
        expect(integration.reload.plans).to eq([])
      end
    end

    context "with plans null" do
      let(:plans) { nil }

      it "keeps the sold plans" do
        expect(result["data"]["updateAgentStorefrontIntegration"]["plans"].map { it["planCode"] }).to eq(["count_per_call"])
        expect(integration.reload.plans.map { it["plan_code"] }).to eq(["count_per_call"])
      end
    end

    context "with a maximum below the minimum" do
      let(:plans) { [{planCode: plan.code, minimumTopupCents: 5000, maximumTopupCents: 2000}] }

      it "returns a validation error on the plans" do
        expect_unprocessable_entity(result, details: {plans: ["value_is_invalid"]})
      end
    end

    context "with a plan that has a subscription fee" do
      let(:plans) { [{planCode: create(:plan, organization:, amount_cents: 100).code}] }

      it "returns a validation error on the plans" do
        expect_unprocessable_entity(result, details: {plans: ["plan_not_usage_only"]})
      end
    end
  end

  context "when the payment connection changes" do
    let(:other_provider) { create(:stripe_provider, organization:, code: "stripe_other") }
    let(:input) { {id: integration.id, paymentProviderCode: other_provider.code} }

    it "updates the connection" do
      expect(result["data"]["updateAgentStorefrontIntegration"]["paymentProviderCode"]).to eq("stripe_other")
    end

    context "when an agent has paid through the current connection" do
      let(:registration) { create(:agent_registration, storefront: integration) }

      before do
        Agents::Billing::EnrollService.call!(storefront: integration, registration:, plan_code: plan.code)
        create(:stripe_customer, customer: registration.customer, payment_provider: integration.stripe_provider)
      end

      it "refuses and reports the locked connection" do
        expect_unprocessable_entity(result, details: {paymentProviderCode: ["agent_storefront_has_enrolled_agents"]})
        expect(integration.reload.payment_provider_code).not_to eq("stripe_other")
      end

      it "reads as locked" do
        read = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: "organization:integrations:view",
          query: "query($id: ID!) { integration(id: $id) { ... on AgentStorefrontIntegration { hasEnrolledAgents hasAgentsWithStripeCustomer } } }",
          variables: {id: integration.id}
        )

        expect(read["data"]["integration"]).to eq("hasEnrolledAgents" => true, "hasAgentsWithStripeCustomer" => true)
      end
    end
  end

  context "when the code is already used" do
    let(:input) { {id: integration.id, code: "taken"} }

    before { create(:agent_storefront_integration, organization:, code: "taken") }

    it "returns a validation error on the code" do
      expect_unprocessable_entity(result, details: {code: ["value_already_exist"]})
    end
  end

  context "when the storefront does not belong to the organization" do
    let(:input) { {id: create(:agent_storefront_integration, organization: create(:organization)).id, name: "x"} }

    it "returns a not found error" do
      expect_not_found(result)
    end
  end

  context "when the organization lacks the agent storefront premium integration" do
    before { organization.update!(premium_integrations: %w[events_targeting_wallets]) }

    it "returns a not allowed error" do
      expect_graphql_error(result:, message: "premium_integration_missing")
    end
  end
end
