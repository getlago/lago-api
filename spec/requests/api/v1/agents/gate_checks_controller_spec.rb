# frozen_string_literal: true

require "rails_helper"

describe Api::V1::Agents::GateChecksController, :premium do
  subject { post_with_token(organization, "/api/v1/agents/gate_checks", {gate_check: params}) }

  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront events_targeting_wallets]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:registration) { create(:agent_registration, storefront:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:token) do
    JWT.encode(
      {iss: storefront.agent_url, sub: registration.id, scope: storefront.scope, iat: Time.current.to_i, exp: 5.minutes.from_now.to_i},
      RsaPrivateKey, "RS256", {typ: "at+jwt"}
    )
  end
  let(:params) do
    {storefront_code: storefront.code, token:, billable_metric_code: billable_metric.code, estimated_call_cost_cents: 1}
  end

  before do
    create(:standard_charge, plan:, billable_metric:, accepts_target_wallet: true)
    storefront.update!(plans: [{plan_code: plan.code}])
  end

  include_examples "requires API permission", "agent", "write"

  context "with a funded agent" do
    before do
      wallet = Agents::Billing::EnrollService.call!(storefront:, registration:, plan_code: plan.code).wallet
      wallet.update!(balance_cents: 1_500_000, credits_balance: 15_000)
    end

    it "renders the pass" do
      subject
      expect(response).to have_http_status(:ok)
      expect(json[:gate_check]).to eq(
        allowed: true, reason: nil, external_subscription_id: "agent_#{registration.id}",
        wallet_code: "agent_credits", balance_credits: "15000.0", billing_instructions: nil
      )
    end
  end

  context "with an agent that is not enrolled" do
    it "renders the refusal with the billing instructions" do
      subject
      expect(response).to have_http_status(:ok)
      expect(json[:gate_check]).to eq(
        allowed: false, reason: "enrollment_required", external_subscription_id: nil,
        wallet_code: nil, balance_credits: nil, billing_instructions: "#{storefront.agent_url}/BILLING.md"
      )
    end
  end

  context "with an invalid token" do
    let(:token) { "invalid" }

    it "answers 422 with the field" do
      subject
      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error_details]).to eq(token: ["invalid_token"])
    end
  end

  context "with the audit log watched" do
    before { allow(Utils::ApiLog).to receive(:produce) }

    it "produces no audit log" do
      subject
      expect(Utils::ApiLog).not_to have_received(:produce)
    end
  end

  context "with an unknown storefront code" do
    let(:params) { super().merge(storefront_code: "unknown") }

    it "answers 404" do
      subject
      expect(response).to be_not_found_error("agent_storefront")
    end
  end

  context "without the gate_check root" do
    subject { post_with_token(organization, "/api/v1/agents/gate_checks", params) }

    it "answers 400" do
      subject
      expect(response).to have_http_status(:bad_request)
    end
  end

  context "without the agent storefront integration" do
    let(:organization) { create(:organization, premium_integrations: %w[events_targeting_wallets]) }

    it "answers 403" do
      subject
      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("feature_unavailable")
    end
  end
end
