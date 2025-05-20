# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransaction, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:wallet) }
    it { is_expected.to belong_to(:invoice).optional }
    it { is_expected.to belong_to(:credit_note).optional }
    it { is_expected.to belong_to(:organization) }
  end

  describe "enums" do
    it "defines expected enum values" do
      expect(described_class.defined_enums).to include(
        "status" => hash_including("pending", "settled", "failed"),
        "transaction_status" => hash_including("purchased", "granted", "voided", "invoiced"),
        "transaction_type" => hash_including("inbound", "outbound"),
        "source" => hash_including("manual", "interval", "threshold")
      )
    end
  end

  describe "#mark_as_failed!" do
    let(:transaction) { create(:wallet_transaction, status: :pending) }

    it "marks the transaction as failed" do
      expect { transaction.mark_as_failed! }
        .to change(transaction, :status).from("pending").to("failed")
        .and change(transaction, :failed_at).from(nil)
    end
  end
end
