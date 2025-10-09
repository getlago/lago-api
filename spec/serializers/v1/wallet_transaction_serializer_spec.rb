# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::WalletTransactionSerializer do
  subject(:serializer) do
    described_class.new(wallet_transaction, root_name: "wallet_transaction", includes:)
  end

  let(:wallet_transaction) { create(:wallet_transaction) }

  context "when includes is empty" do
    let(:includes) { [] }

    it "serializes the object" do
      result = JSON.parse(serializer.to_json)

      expect(result["wallet_transaction"]).to include(
        "lago_id" => wallet_transaction.id,
        "lago_wallet_id" => wallet_transaction.wallet_id,
        "status" => wallet_transaction.status,
        "source" => wallet_transaction.source,
        "transaction_status" => wallet_transaction.transaction_status,
        "transaction_type" => wallet_transaction.transaction_type,
        "amount" => wallet_transaction.amount.to_s,
        "credit_amount" => wallet_transaction.credit_amount.to_s,
        "settled_at" => wallet_transaction.settled_at&.iso8601,
        "failed_at" => wallet_transaction.failed_at&.iso8601,
        "created_at" => wallet_transaction.created_at.iso8601,
        "invoice_requires_successful_payment" => wallet_transaction.invoice_requires_successful_payment?,
        "metadata" => wallet_transaction.metadata,
        "name" => "Custom Transaction Name"
      )
    end
  end

  context "when includes wallet is set" do
    let(:includes) { %i[wallet] }
    let(:wallet) { wallet_transaction.wallet }

    it "includes the wallet" do
      result = JSON.parse(serializer.to_json)

      expect(result["wallet_transaction"]["wallet"]).to include(
        "lago_id" => wallet.id,
        "status" => wallet.status,
        "created_at" => wallet.created_at.iso8601,
        "expiration_at" => wallet.expiration_at&.iso8601
      )
    end
  end
end
