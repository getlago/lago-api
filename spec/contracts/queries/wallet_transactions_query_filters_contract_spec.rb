# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queries::WalletTransactionsQueryFiltersContract do
  subject(:result) { described_class.new.call(filters.to_h) }

  let(:filters) { {} }

  context "when wallet_id is provided" do
    let(:filters) { {wallet_id: "wallet-123"} }

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when wallet_id is missing" do
    let(:filters) { {} }

    it "is invalid" do
      expect(result.success?).to be(false)
      expect(result.errors.to_h).to include(wallet_id: ["is missing"])
    end
  end

  context "when wallet_id is blank" do
    let(:filters) { {wallet_id: ""} }

    it "is invalid" do
      expect(result.success?).to be(false)
      expect(result.errors.to_h).to include(wallet_id: ["must be filled"])
    end
  end

  context "when filtering by transaction_type" do
    let(:filters) { {wallet_id: "wallet-123", transaction_type: "inbound"} }

    it "is valid" do
      expect(result.success?).to be(true)
    end

    context "when filter is an array" do
      let(:filters) { {wallet_id: "wallet-123", transaction_type: ["inbound", "outbound"]} }

      it "is valid" do
        expect(result.success?).to be(true)
      end
    end
  end

  context "when filtering by transaction_status" do
    let(:filters) { {wallet_id: "wallet-123", transaction_status: "granted"} }

    it "is valid" do
      expect(result.success?).to be(true)
    end

    context "when filter is an array" do
      let(:filters) { {wallet_id: "wallet-123", transaction_status: ["granted", "invoiced"]} }

      it "is valid" do
        expect(result.success?).to be(true)
      end
    end
  end

  context "when filtering by status" do
    let(:filters) { {wallet_id: "wallet-123", status: "pending"} }

    it "is valid" do
      expect(result.success?).to be(true)
    end

    context "when filter is an array" do
      let(:filters) { {wallet_id: "wallet-123", status: ["pending", "settled"]} }

      it "is valid" do
        expect(result.success?).to be(true)
      end
    end
  end

  context "when filters are invalid" do
    it_behaves_like "an invalid filter", :transaction_type, "random", ["must be one of: inbound, outbound or must be an array"]
    it_behaves_like "an invalid filter", :transaction_type, ["inbound", "random"], {1 => ["must be one of: inbound, outbound"]}
    it_behaves_like "an invalid filter", :transaction_status, "random", ["must be one of: purchased, granted, voided, invoiced or must be an array"]
    it_behaves_like "an invalid filter", :transaction_status, ["granted", "random"], {1 => ["must be one of: purchased, granted, voided, invoiced"]}
    it_behaves_like "an invalid filter", :status, "random", ["must be one of: pending, settled, failed or must be an array"]
    it_behaves_like "an invalid filter", :status, ["pending", "random"], {1 => ["must be one of: pending, settled, failed"]}
  end
end
