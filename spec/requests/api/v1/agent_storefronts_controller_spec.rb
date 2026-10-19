# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::AgentStorefrontsController, :premium do
  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront events_targeting_wallets]) }
  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:storefront) { create(:agent_storefront_integration, organization:, code: "acme_api", stripe_provider:) }

  before do
    stripe_provider
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LAGO_REDIS_CACHE_URL").and_return("redis://redis:6379")
    allow(ENV).to receive(:[]).with("LAGO_DISABLE_WALLET_REFRESH").and_return(nil)
  end

  shared_examples "an endpoint behind the agent storefront premium integration" do
    context "without the premium integration" do
      let(:organization) { create(:organization, premium_integrations: %w[events_targeting_wallets]) }

      it "returns a feature unavailable error" do
        subject
        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  describe "POST /api/v1/agent_storefronts" do
    subject { post_with_token(organization, "/api/v1/agent_storefronts", {agent_storefront: params}) }

    let(:params) do
      {
        code: "acme_api",
        name: "Acme API",
        payment_provider_code: stripe_provider.code,
        resource_endpoint: "https://api.acme.example/v1"
      }
    end

    include_examples "requires API permission", "agent_storefront", "write"
    include_examples "an endpoint behind the agent storefront premium integration"

    it "creates and renders the storefront" do
      expect { subject }.to change { organization.agent_storefront_integrations.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(json[:agent_storefront]).to include(
        lago_organization_id: organization.id,
        code: "acme_api",
        name: "Acme API",
        payment_provider_code: stripe_provider.code,
        resource_endpoint: "https://api.acme.example/v1",
        resource_instructions: nil,
        scope: "acme_api:use"
      )
      expect(json[:agent_storefront][:lago_id]).to be_present
    end

    context "with plans" do
      let(:plan) { create(:plan, organization:) }
      let(:params) { super().merge(plans: [{plan_code: plan.code, minimum_topup_cents: 500, maximum_topup_cents: 10_000}]) }

      it "creates the storefront with the plans it sells" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:agent_storefront][:plans]).to eq([{plan_code: plan.code, minimum_topup_cents: 500, maximum_topup_cents: 10_000}])
      end
    end

    context "with an unknown stripe connection" do
      let(:params) { super().merge(payment_provider_code: "unknown") }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(payment_provider_code: %w[payment_provider_not_found])
      end
    end

    context "without events targeting wallets" do
      let(:organization) { create(:organization, premium_integrations: %w[agent_storefront]) }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(base: %w[events_targeting_wallets_disabled])
      end
    end
  end

  describe "PUT /api/v1/agent_storefronts/:code" do
    subject { put_with_token(organization, "/api/v1/agent_storefronts/#{storefront.code}", {agent_storefront: params}) }

    let(:params) { {name: "Acme API v2", resource_instructions: "https://acme.example/agents"} }

    before { storefront }

    include_examples "requires API permission", "agent_storefront", "write"
    include_examples "an endpoint behind the agent storefront premium integration"

    it "updates and renders the storefront" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:agent_storefront]).to include(
        code: "acme_api",
        name: "Acme API v2",
        resource_instructions: "https://acme.example/agents",
        scope: "acme_api:use"
      )
    end

    context "with plans" do
      let(:plan) { create(:plan, organization:) }
      let(:params) { {plans: [{plan_code: plan.code, minimum_topup_cents: 500, maximum_topup_cents: 10_000}]} }

      it "saves and renders them" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:agent_storefront][:plans]).to eq([{plan_code: plan.code, minimum_topup_cents: 500, maximum_topup_cents: 10_000}])
      end

      context "when the list is empty" do
        let(:params) { {plans: []} }

        before { storefront.update!(plans: [{plan_code: plan.code}]) }

        it "clears them" do
          subject

          expect(response).to have_http_status(:ok)
          expect(json[:agent_storefront][:plans]).to eq([])
        end
      end
    end

    context "with an http url" do
      let(:params) { {resource_instructions: "http://acme.example/agents"} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(resource_instructions: %w[url_is_invalid])
      end
    end

    context "with an unknown code" do
      subject { put_with_token(organization, "/api/v1/agent_storefronts/unknown", {agent_storefront: params}) }

      it "returns a not found error" do
        subject
        expect(response).to be_not_found_error("agent_storefront")
      end
    end
  end

  describe "DELETE /api/v1/agent_storefronts/:code" do
    subject { delete_with_token(organization, "/api/v1/agent_storefronts/#{storefront.code}") }

    before { storefront }

    include_examples "requires API permission", "agent_storefront", "write"
    include_examples "an endpoint behind the agent storefront premium integration"

    it "destroys and renders the storefront" do
      expect { subject }.to change { organization.agent_storefront_integrations.count }.by(-1)

      expect(response).to have_http_status(:ok)
      expect(json[:agent_storefront][:code]).to eq("acme_api")
    end

    context "with an unknown code" do
      subject { delete_with_token(organization, "/api/v1/agent_storefronts/unknown") }

      it "returns a not found error" do
        subject
        expect(response).to be_not_found_error("agent_storefront")
      end
    end
  end

  describe "GET /api/v1/agent_storefronts/:code" do
    subject { get_with_token(organization, "/api/v1/agent_storefronts/#{storefront.code}") }

    before { storefront }

    include_examples "requires API permission", "agent_storefront", "read"
    include_examples "an endpoint behind the agent storefront premium integration"

    it "renders the storefront" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:agent_storefront]).to include(lago_id: storefront.id, code: "acme_api", scope: "acme_api:use")
    end

    context "with a storefront of another organization" do
      let(:storefront) { create(:agent_storefront_integration, organization: create(:organization), code: "acme_api") }

      it "returns a not found error" do
        subject
        expect(response).to be_not_found_error("agent_storefront")
      end
    end
  end

  describe "GET /api/v1/agent_storefronts" do
    subject { get_with_token(organization, "/api/v1/agent_storefronts") }

    before do
      storefront
      create(:agent_storefront_integration, organization: create(:organization), code: "other")
    end

    include_examples "requires API permission", "agent_storefront", "read"
    include_examples "an endpoint behind the agent storefront premium integration"

    it "renders the storefronts of the organization" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:agent_storefronts].map { it[:code] }).to eq(["acme_api"])
      expect(json[:meta][:total_count]).to eq(1)
    end
  end
end
