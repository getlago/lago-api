# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::X402::GateChecksController, :premium do
  let(:organization) { create(:organization, feature_flags: ["x402_payments"]) }
  let(:connection) { create(:x402_connection, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }

  describe "POST /api/v1/x402/gate_checks" do
    subject { post_with_token(organization, "/api/v1/x402/gate_checks", {gate_check: params}) }

    let(:params) do
      {connection_code: connection.code, wallet_code: "agent_credits", agent_address: "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
       resource: "POST /v1/generate", plan_code: plan.code, billable_metric_code: "api_calls", amount_cents: 100, estimated_call_cost_cents: 1}
    end

    it "returns a top-up challenge for an unknown agent" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:gate_check]).to include(
        external_subscription_id: nil,
        requirements: [{scheme: "exact", network: "eip155:84532", asset: "usdc", pay_to: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", amount_atomic: "1000000", max_timeout_seconds: 60}]
      )
    end
  end
end
