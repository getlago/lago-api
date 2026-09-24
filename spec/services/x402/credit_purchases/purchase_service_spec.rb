# frozen_string_literal: true

require "rails_helper"

RSpec.describe X402::CreditPurchases::PurchaseService do
  subject(:result) { described_class.call(organization:, params:) }

  include_context "with an x402 payment"

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:, code: "agent_api", amount_cents: 0, amount_currency: "USD") }
  let(:wallet_rate_amount) { "0.01" }
  let(:params) do
    {
      connection_code: connection.code,
      wallet_code: "agent_credits",
      plan_code: plan.code,
      payment:,
      payment_requirements:,
      wallet: {"name" => "Agent credits", "rate_amount" => wallet_rate_amount, "currency" => "USD"}
    }
  end

  context "when the agent pays for the first time" do
    it "settles through CDP and grants spendable credits to a new customer" do
      settlement = result.settlement
      wallet_transaction = settlement.wallet_transaction

      expect(settlement).to have_attributes(status: "settled", transaction_hash: settle_tx_hash, payer_address: agent_address, settled_amount_cents: 100)
      expect(settlement.customer).to have_attributes(x402_agent_address: agent_address, external_id: "x402_#{agent_address}", currency: "USD")
      expect(settlement.subscription).to have_attributes(status: "active", plan:, external_id: "x402_#{agent_address}_agent_api")
      expect(wallet_transaction).to have_attributes(status: "settled", transaction_status: "purchased", source: "x402", credit_amount: 100)
      expect(wallet_transaction.wallet.reload).to have_attributes(code: "agent_credits", balance_cents: 100, credits_balance: 100)
      expect(a_request(:post, verify_url)).to have_been_made.once
      expect(a_request(:post, settle_url)).to have_been_made.once
    end
  end

  context "when the agent already holds a wallet" do
    let(:customer) { create(:customer, organization:, currency: "USD", x402_agent_address: agent_address) }
    let(:subscription) { create(:subscription, customer:, plan:, external_id: "x402_#{agent_address}_agent_api") }
    let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", rate_amount: "0.01", balance_cents: 50, credits_balance: 50) }

    before do
      subscription
      wallet
    end

    it "tops up the existing wallet on the existing subscription" do
      expect { result }.not_to change(Customer, :count)
      expect(result.settlement).to have_attributes(customer:, subscription:)
      expect(wallet.reload).to have_attributes(balance_cents: 150, credits_balance: 150)
    end
  end

  context "with a rate that does not divide the amount" do
    let(:amount_atomic) { "10000000" }
    let(:wallet_rate_amount) { "0.0007" }

    it "floors the credits to five decimals (D11, QA 9)" do
      expect(result.settlement.wallet_transaction.credit_amount).to eq(BigDecimal("14285.71428"))
    end
  end
end
