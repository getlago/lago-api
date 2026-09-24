# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::X402::CreditPurchasesController, :premium do
  include_context "with an x402 payment"

  let(:organization) { create(:organization, feature_flags: ["x402_payments"]) }
  let(:plan) { create(:plan, organization:, code: "agent_api", amount_cents: 0, amount_currency: "USD") }

  describe "POST /api/v1/x402/credit_purchases" do
    subject { post_with_token(organization, "/api/v1/x402/credit_purchases", {credit_purchase: params}) }

    let(:params) do
      {connection_code: connection.code, wallet_code: "agent_credits", plan_code: plan.code, payment:, payment_requirements:,
       wallet: {name: "Agent credits", rate_amount: "0.01", currency: "USD"}}
    end

    it "settles the payment and returns the grant" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:x402_settlement]).to include(
        status: "settled",
        replayed: false,
        network: "eip155:84532",
        transaction_hash: settle_tx_hash,
        payer_address: agent_address,
        external_subscription_id: "x402_#{agent_address}_agent_api",
        credits_granted: "100.0",
        settled_amount_cents: 100
      )
    end
  end
end
