# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::SettleService do
  subject(:service) { described_class.new(wallet_transaction:) }

  let(:wallet_transaction) { create(:wallet_transaction, status: "pending", settled_at: nil) }

  describe ".call" do
    it "updates wallet_transaction status" do
      expect {
        service.call
      }.to change { wallet_transaction.reload.status }.from("pending").to("settled")
        .and change(wallet_transaction, :settled_at).from(nil)
    end

    it "enqueues a SendWebhookJob for each wallet transaction" do
      expect do
        service.call
      end.to have_enqueued_job(SendWebhookJob).with("wallet_transaction.updated", WalletTransaction)
    end

    it "produces an activity log" do
      described_class.call(wallet_transaction:)

      expect(Utils::ActivityLog).to have_produced("wallet_transaction.updated").after_commit.with(wallet_transaction)
    end
  end
end
