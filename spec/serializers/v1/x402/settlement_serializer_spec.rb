# frozen_string_literal: true

require "rails_helper"

describe V1::X402::SettlementSerializer do
  subject(:serializer) { described_class.new(settlement, root_name: "x402_settlement", replayed:) }

  let(:replayed) { false }
  let(:payload) { JSON.parse(serializer.to_json)["x402_settlement"] }

  context "with a granted purchase" do
    let(:customer) { build_stubbed(:customer) }
    let(:subscription) { build_stubbed(:subscription, customer:, external_id: "x402_agent_api") }
    let(:wallet_transaction) { build_stubbed(:wallet_transaction, credit_amount: "10000.0") }
    let(:settlement) { build_stubbed(:x402_settlement, customer:, subscription:, wallet_transaction:, settled_amount_cents: 1000) }

    it "renders the grant" do
      expect(payload).to eq(
        "lago_id" => settlement.id, "status" => "settled", "replayed" => false,
        "network" => "eip155:84532", "transaction_hash" => settlement.transaction_hash, "payer_address" => settlement.payer_address,
        "lago_customer_id" => customer.id, "lago_wallet_transaction_id" => wallet_transaction.id,
        "external_subscription_id" => "x402_agent_api", "credits_granted" => "10000.0", "settled_amount_cents" => 1000,
        "reconcile_after" => nil
      )
    end
  end

  context "with a pending purchase" do
    let(:settlement) { build_stubbed(:x402_settlement, :pending, transaction_hash: "0x#{"cd" * 32}", reconcile_after: Time.zone.parse("2026-09-24T10:02:00Z")) }

    it "renders no hash" do
      expect(payload["transaction_hash"]).to be_nil
    end

    it "renders when reconciliation runs" do
      expect(payload["reconcile_after"]).to eq("2026-09-24T10:02:00Z")
    end

    it "renders no grant" do
      expect(payload.values_at("credits_granted", "external_subscription_id", "lago_wallet_transaction_id")).to eq([nil, nil, nil])
    end
  end

  context "with a replay" do
    let(:replayed) { true }
    let(:settlement) { build_stubbed(:x402_settlement) }

    it "marks it replayed" do
      expect(payload["replayed"]).to be(true)
    end
  end
end
