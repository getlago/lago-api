# frozen_string_literal: true

require "rails_helper"

describe CatalogWallets::Ledger::SettleService do
  subject(:result) { described_class.call(wallet_transaction:) }

  let(:organization) { create(:organization) }

  let(:wallet) { create(:catalog_wallet, organization:, balance_cents: 5_000) }
  let(:wallet_transaction) do
    create(:catalog_wallet_transaction, :pending, organization:, catalog_wallet: wallet, credit_amount_cents: 10_000)
  end

  before { allow(CatalogWallets::ThresholdTopUpService).to receive(:call).and_call_original }

  it "settles the entry" do
    freeze_time do
      expect(result).to be_success
      expect(result.wallet_transaction.reload).to have_attributes(
        status: "settled",
        settled_at: Time.current,
        failed_at: nil,
        remaining_credit_amount_cents: 10_000
      )
    end
  end

  it "raises the balance by the entry's credit" do
    expect { result }.to change { wallet.reload.balance_cents }.from(5_000).to(15_000)
  end

  it "leaves the ongoing balance untouched" do
    expect { result }.not_to change { wallet.reload.ongoing_balance_cents }.from(0)
  end

  it "checks the top-up threshold once the transaction commits" do
    ApplicationRecord.transaction do
      result

      expect(CatalogWallets::ThresholdTopUpService).not_to have_received(:call)
    end

    expect(CatalogWallets::ThresholdTopUpService).to have_received(:call).with(wallet:).once
  end

  context "when the entry is loaded without its wallet" do
    subject(:result) { described_class.call(wallet_transaction: loaded_transaction) }

    let(:loaded_transaction) { CatalogWalletTransaction.find(wallet_transaction.id) }

    before { loaded_transaction }

    it "takes the customer lock without loading the customer" do
      statements = capture_sql { result }

      expect(result).to be_success
      expect(statements).not_to include(a_string_matching(/FROM "customers"/))
    end
  end

  context "when the pending entry holds no remaining credit" do
    let(:wallet_transaction) do
      create(
        :catalog_wallet_transaction,
        :pending,
        organization:,
        catalog_wallet: wallet,
        credit_amount_cents: 10_000,
        remaining_credit_amount_cents: 0
      )
    end

    it "makes the whole credit spendable" do
      expect(result.wallet_transaction.reload.remaining_credit_amount_cents).to eq(10_000)
    end
  end

  context "when the entry failed" do
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, :failed, organization:, catalog_wallet: wallet, credit_amount_cents: 10_000)
    end

    it "settles it" do
      expect { result }.to change { wallet.reload.balance_cents }.from(5_000).to(15_000)

      expect(result).to be_success
      expect(wallet_transaction.reload).to have_attributes(status: "settled", failed_at: nil)
    end
  end

  context "when the entry is already settled" do
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, organization:, catalog_wallet: wallet, credit_amount_cents: 10_000, settled_at: 2.days.ago)
    end

    it "changes nothing" do
      expect { result }.not_to change { [wallet.reload.balance_cents, wallet_transaction.reload.settled_at] }

      expect(result).to be_success
      expect(CatalogWallets::ThresholdTopUpService).not_to have_received(:call)
    end
  end

  context "when another instance of the entry was settled first" do
    before { described_class.call!(wallet_transaction: CatalogWalletTransaction.find(wallet_transaction.id)) }

    it "does not raise the balance twice" do
      expect { result }.not_to change { wallet.reload.balance_cents }.from(15_000)

      expect(result).to be_success
    end
  end

  context "when the wallet's balance moved since it was loaded" do
    let(:other_transaction) do
      create(
        :catalog_wallet_transaction,
        :pending,
        organization:,
        catalog_wallet: CatalogWallet.find(wallet.id),
        credit_amount_cents: 2_000
      )
    end

    before do
      wallet_transaction
      described_class.call!(wallet_transaction: other_transaction)
    end

    it "adds the credit to the current balance" do
      expect(result).to be_success
      expect(wallet.reload.balance_cents).to eq(5_000 + 2_000 + 10_000) # balance before + other entry + this entry
    end
  end

  context "when the wallet was deleted and its code is in use again" do
    let(:wallet) { create(:catalog_wallet, organization:, balance_cents: 5_000, deleted_at: 1.day.ago) }

    before { create(:catalog_wallet, organization:, customer: wallet.customer, contract: wallet.contract, code: wallet.code) }

    it "still settles the entry" do
      expect { result }.to change { wallet.reload.balance_cents }.from(5_000).to(15_000)

      expect(result).to be_success
    end
  end

  context "when the entry is outbound" do
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, :invoice_application, organization:, catalog_wallet: wallet)
    end

    it "refuses it" do
      expect { result }.not_to change { wallet.reload.balance_cents }

      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("wallet_transaction_not_inbound")
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
