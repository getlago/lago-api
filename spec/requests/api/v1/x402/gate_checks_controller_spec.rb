# frozen_string_literal: true

require "rails_helper"

describe Api::V1::X402::GateChecksController, :premium do
  subject { post_with_token(organization, "/api/v1/x402/gate_checks", {gate_check: params}) }

  let(:organization) { create(:organization, feature_flags: ["x402_payments"], premium_integrations: ["events_targeting_wallets"]) }
  let(:connection) { create(:x402_connection, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:agent_address) { "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2" }
  let(:params) do
    {
      connection_code: connection.code, wallet_code: "agent_credits", agent_address:, resource: "POST /v1/generate",
      plan_code: plan.code, billable_metric_code: billable_metric.code, amount_cents: 1_000, estimated_call_cost_cents: 1
    }
  end

  before { create(:standard_charge, plan:, billable_metric:, accepts_target_wallet: true) }

  include_examples "requires API permission", "x402", "write"

  context "with a funded agent" do
    let(:customer) { create(:customer, organization:, x402_agent_address: agent_address) }
    let(:external_id) { "x402_#{agent_address}_#{plan.code}" }

    before do
      create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true, balance_cents: 1_500, credits_balance: 15)
      create(:subscription, customer:, plan:, external_id:)
    end

    it "renders the pass" do
      subject
      expect(json[:gate_check]).to eq(balance_credits: "15.0", requirements: nil, external_subscription_id: external_id)
    end
  end

  context "with a stranger" do
    it "renders the challenge" do
      subject
      expect(json[:gate_check]).to eq(
        balance_credits: "0.0", external_subscription_id: nil,
        requirements: [{
          scheme: "exact", network: "eip155:84532", asset: "usdc", asset_address: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
          extra: {name: "USDC", version: "2"}, pay_to: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
          amount_atomic: "10000000", max_timeout_seconds: 60
        }]
      )
    end
  end

  context "with the audit log watched" do
    before { allow(Utils::ApiLog).to receive(:produce) }

    it "produces no audit log" do
      subject
      expect(Utils::ApiLog).not_to have_received(:produce)
    end
  end

  context "with the API key cache watched" do
    before { allow(ApiKeys::CacheService).to receive(:call).and_call_original }

    it "reads the API key from the database" do
      subject
      expect(ApiKeys::CacheService).to have_received(:call).with(anything, with_cache: false)
    end
  end

  context "when the connection refuses strangers" do
    let(:connection) { create(:x402_connection, organization:, auto_create_customers: false) }

    it "answers 422 with the code" do
      subject
      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error_details]).to eq(base: ["buyer_not_recognized"])
    end
  end

  context "when /supported is unavailable" do
    include_context "with an x402 payment"

    let(:organization) { create(:organization, feature_flags: ["x402_payments"], premium_integrations: ["events_targeting_wallets"]) }
    let(:connection) { create(:x402_connection, :solana, organization:, cdp_api_key_id:, cdp_api_key_secret:) }
    let(:params) { super().except(:agent_address) }

    before { stub_request(:get, "#{cdp_facilitator_url}/supported").to_return(status: 503, body: "{}") }

    it "answers 422 with third_party_error" do
      subject
      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:code]).to eq("third_party_error")
    end
  end

  context "with an unknown connection code" do
    let(:params) { super().merge(connection_code: "unknown") }

    it "answers 404" do
      subject
      expect(response).to be_not_found_error("connection")
    end
  end

  context "without the gate_check root" do
    subject { post_with_token(organization, "/api/v1/x402/gate_checks", params) }

    it "answers 400" do
      subject
      expect(response).to have_http_status(:bad_request)
    end
  end

  context "when the x402_payments flag is off" do
    let(:organization) { create(:organization, premium_integrations: ["events_targeting_wallets"]) }

    it "answers 403" do
      subject
      expect(response).to have_http_status(:forbidden)
    end
  end
end
