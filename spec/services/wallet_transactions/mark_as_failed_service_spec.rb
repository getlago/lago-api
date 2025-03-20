# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::MarkAsFailedService, type: :service do
  subject(:service) { described_class.new(wallet_transaction:) }

  let(:wallet_transaction) { create(:wallet_transaction, status: "pending") }

  describe ".call" do
    context "when wallet_transaction is nil" do
      let(:wallet_transaction) { nil }

      it "returns an empty result" do
        result = service.call
        expect(result.wallet_transaction).to be_nil
      end
    end

    context "when wallet_transaction is already failed" do
      let(:wallet_transaction) { create(:wallet_transaction, status: "failed") }

      it "does not change the wallet_transaction status" do
        expect { service.call }.not_to change(wallet_transaction, :status)
      end

      it "does not enqueue a SendWebhookJob" do
        expect { service.call }.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context "when wallet_transaction is not failed" do
      it "updates the wallet_transaction status to failed" do
        expect {
          service.call
        }.to change { wallet_transaction.reload.status }.from("pending").to("failed")
      end

      it "enqueues a SendWebhookJob with appropriate arguments" do
        expect {
          service.call
        }.to have_enqueued_job(SendWebhookJob).with("wallet_transaction.updated", wallet_transaction)
      end
    end
  end
end
