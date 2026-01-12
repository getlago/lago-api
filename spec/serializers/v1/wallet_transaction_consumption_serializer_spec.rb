# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::WalletTransactionConsumptionSerializer do
  subject(:serializer) do
    described_class.new(consumption, root_name: "wallet_transaction_consumption", includes:)
  end

  let(:consumption) { create(:wallet_transaction_consumption) }
  let(:includes) { [] }

  context "when includes is empty" do
    it "serializes the object" do
      result = JSON.parse(serializer.to_json)

      expect(result["wallet_transaction_consumption"]).to include(
        "lago_id" => consumption.id,
        "lago_inbound_wallet_transaction_id" => consumption.inbound_wallet_transaction_id,
        "lago_outbound_wallet_transaction_id" => consumption.outbound_wallet_transaction_id,
        "amount_cents" => consumption.consumed_amount_cents,
        "created_at" => consumption.created_at.iso8601
      )
      expect(result["wallet_transaction_consumption"]).not_to have_key("inbound_wallet_transaction")
      expect(result["wallet_transaction_consumption"]).not_to have_key("outbound_wallet_transaction")
    end
  end

  context "when includes inbound_wallet_transaction is set" do
    let(:includes) { %i[inbound_wallet_transaction] }

    it "includes the inbound wallet transaction" do
      result = JSON.parse(serializer.to_json)

      expect(result["wallet_transaction_consumption"]["inbound_wallet_transaction"]).to include(
        "lago_id" => consumption.inbound_wallet_transaction.id,
        "transaction_type" => "inbound"
      )
    end
  end

  context "when includes outbound_wallet_transaction is set" do
    let(:includes) { %i[outbound_wallet_transaction] }

    it "includes the outbound wallet transaction" do
      result = JSON.parse(serializer.to_json)

      expect(result["wallet_transaction_consumption"]["outbound_wallet_transaction"]).to include(
        "lago_id" => consumption.outbound_wallet_transaction.id,
        "transaction_type" => "outbound"
      )
    end
  end

  context "when both inbound and outbound wallet transactions are included" do
    let(:includes) { %i[inbound_wallet_transaction outbound_wallet_transaction] }

    it "includes both wallet transactions" do
      result = JSON.parse(serializer.to_json)

      expect(result["wallet_transaction_consumption"]["inbound_wallet_transaction"]).to include(
        "lago_id" => consumption.inbound_wallet_transaction.id
      )
      expect(result["wallet_transaction_consumption"]["outbound_wallet_transaction"]).to include(
        "lago_id" => consumption.outbound_wallet_transaction.id
      )
    end
  end
end
