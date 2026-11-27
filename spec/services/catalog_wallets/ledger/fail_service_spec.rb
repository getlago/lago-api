# frozen_string_literal: true

require "rails_helper"

describe CatalogWallets::Ledger::FailService do
  subject(:result) { described_class.call(wallet_transaction:) }

  let(:organization) { create(:organization) }
  let(:wallet) { create(:catalog_wallet, organization:, balance_cents: 5_000) }
  let(:wallet_transaction) do
    create(:catalog_wallet_transaction, :pending, organization:, catalog_wallet: wallet, credit_amount_cents: 10_000)
  end

  before { allow(CatalogWallets::ThresholdTopUpService).to receive(:call).and_call_original }

  it "fails the entry" do
    freeze_time do
      expect(result).to be_success
      expect(result.wallet_transaction.reload).to have_attributes(status: "failed", failed_at: Time.current, settled_at: nil)
    end
  end

  it "leaves the balance as it is" do
    expect { result }.not_to change { wallet.reload.balance_cents }.from(5_000)

    expect(CatalogWallets::ThresholdTopUpService).not_to have_received(:call)
  end

  context "when the entry already failed" do
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, :failed, organization:, catalog_wallet: wallet, failed_at: 2.days.ago)
    end

    it "changes nothing" do
      expect { result }.not_to change { wallet_transaction.reload.failed_at }

      expect(result).to be_success
    end
  end

  context "when the entry is settled" do
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, organization:, catalog_wallet: wallet, credit_amount_cents: 5_000)
    end

    it "keeps its credit" do
      expect { result }.not_to change { [wallet.reload.balance_cents, wallet_transaction.reload.status] }.from([5_000, "settled"])

      expect(result).to be_success
    end
  end

  context "when another instance of the entry was settled first" do
    before { CatalogWallets::Ledger::SettleService.call!(wallet_transaction: CatalogWalletTransaction.find(wallet_transaction.id)) }

    it "keeps it settled" do
      expect(result).to be_success
      expect(wallet_transaction.reload).to be_settled
      expect(wallet.reload.balance_cents).to eq(5_000 + 10_000) # balance before + settled credit
    end
  end

  context "when the customer's wallet lock is held" do
    before { stub_const("Customers::LockService::ACQUIRE_LOCK_TIMEOUT", 0.seconds) }

    around do |test|
      with_advisory_lock("customer-#{wallet.customer_id}-catalog_wallet", lock_released_after: 2.seconds) do
        test.run
      end
    end

    it "raises a lock error" do
      expect { result }.to raise_error(BaseLockService::FailedToAcquireLock)
      expect(wallet_transaction.reload).to be_pending
    end
  end
end
