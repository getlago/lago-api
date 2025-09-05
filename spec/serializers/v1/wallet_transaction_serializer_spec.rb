# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::WalletTransactionSerializer do
  subject(:serializer) do
    described_class.new(wallet_transaction, root_name: "wallet_transaction")
  end

  let(:wallet_transaction) { create(:wallet_transaction) }

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
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
        "name" => nil
      )
    end
  end

  context "when wallet transaction has a name" do
    let(:wallet_transaction) { create(:wallet_transaction, name: "Custom Transaction Name") }

    it "includes the name in serialization" do
      result = JSON.parse(serializer.to_json)

      expect(result["wallet_transaction"]["name"]).to eq("Custom Transaction Name")
    end
  end
end
