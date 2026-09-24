# frozen_string_literal: true

require "rails_helper"

RSpec.describe X402::GateChecks::CheckService do
  subject(:result) { described_class.call(organization:, params:) }

  let(:organization) { create(:organization) }
  let(:connection) { create(:x402_connection, organization:) }
  let(:plan) { create(:plan, organization:, code: "agent_api", amount_cents: 0, amount_currency: "USD") }
  let(:agent_address) { "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359" }
  let(:params) do
    {
      connection_code: connection.code,
      wallet_code: "agent_credits",
      agent_address: agent_address.downcase,
      resource: "POST /v1/generate",
      plan_code: plan.code,
      billable_metric_code: "api_calls",
      amount_cents: 100,
      estimated_call_cost_cents: 1
    }
  end

  context "when the agent is unknown" do
    it "returns a top-up challenge and creates nothing" do
      expect { result }.not_to change(Customer, :count)
      expect(result.requirements).to eq([
        {scheme: "exact", network: "eip155:84532", asset: "usdc", pay_to: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", amount_atomic: "1000000", max_timeout_seconds: 60}
      ])
      expect(result).to have_attributes(balance_credits: 0, external_subscription_id: nil)
    end
  end

  context "when the agent holds credits on an active subscription" do
    let(:customer) { create(:customer, organization:, currency: "USD", x402_agent_address: agent_address) }
    let(:subscription) { create(:subscription, customer:, plan:, external_id: "x402_#{agent_address}_agent_api") }
    let(:balance_cents) { 100 }

    before do
      subscription
      create(:wallet, customer:, code: "agent_credits", currency: "USD", rate_amount: "0.01", balance_cents:,
        credits_balance: balance_cents, ongoing_usage_balance_cents: 3, credits_ongoing_usage_balance: 3)
    end

    it "passes with the subscription to meter the call with" do
      expect(result).to have_attributes(requirements: nil, external_subscription_id: subscription.external_id, balance_credits: 97)
    end

    context "when the balance cannot cover one more call" do
      let(:balance_cents) { 3 }

      it "returns a challenge that still names the subscription" do
        expect(result.requirements).to be_present
        expect(result.external_subscription_id).to eq(subscription.external_id)
      end
    end
  end
end
