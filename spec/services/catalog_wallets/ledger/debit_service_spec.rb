# frozen_string_literal: true

require "rails_helper"

describe CatalogWallets::Ledger::DebitService do
  subject(:result) { described_class.call(wallet:, reason:, consumptions:, invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:catalog_wallet, organization:, customer:, balance_cents: 15_000) }
  let(:older_entry) { create(:catalog_wallet_transaction, organization:, catalog_wallet: wallet, credit_amount_cents: 5_000) }
  let(:newer_entry) { create(:catalog_wallet_transaction, organization:, catalog_wallet: wallet, credit_amount_cents: 10_000) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:first_fee) { create(:fee, invoice:) }
  let(:second_fee) { create(:fee, invoice:) }
  let(:reason) { "invoice_application" }
  let(:consumptions) do
    [
      {inbound_transaction: older_entry, fee: first_fee, credit_amount_cents: 5_000},
      {inbound_transaction: newer_entry, fee: first_fee, credit_amount_cents: 2_000},
      {inbound_transaction: newer_entry, fee: second_fee, credit_amount_cents: 3_000}
    ]
  end

  before { allow(CatalogWallets::ThresholdTopUpService).to receive(:call).and_call_original }

  def race(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(&block)
    rescue => e
      e
    end
  end

  it "writes one outbound entry for the total" do
    freeze_time do
      expect(result).to be_success
      expect(result.wallet_transaction).to have_attributes(
        organization_id: organization.id,
        catalog_wallet_id: wallet.id,
        direction: "outbound",
        status: "settled",
        settled_at: Time.current,
        reason: "invoice_application",
        invoice_id: invoice.id,
        credit_amount_cents: 5_000 + 2_000 + 3_000,
        purchase_amount_cents: nil,
        remaining_credit_amount_cents: nil
      )
    end
  end

  it "records which entry paid which fee" do
    rows = result.wallet_transaction.fundings.map { [it.inbound_transaction_id, it.fee_id, it.credit_amount_cents, it.organization_id] }

    expect(rows).to match_array([
      [older_entry.id, first_fee.id, 5_000, organization.id],
      [newer_entry.id, first_fee.id, 2_000, organization.id],
      [newer_entry.id, second_fee.id, 3_000, organization.id]
    ])
  end

  it "lowers the paying entries and the balance by the same total" do
    result

    expect(older_entry.reload.remaining_credit_amount_cents).to eq(5_000 - 5_000)
    expect(newer_entry.reload.remaining_credit_amount_cents).to eq(10_000 - 2_000 - 3_000)
    expect(wallet.reload).to have_attributes(balance_cents: 15_000 - 10_000, ongoing_balance_cents: 0)
    expect(wallet.balance_cents).to eq(wallet.transactions.inbound.settled.sum(:remaining_credit_amount_cents))
  end

  it "checks the top-up threshold once the transaction commits" do
    ApplicationRecord.transaction do
      result

      expect(CatalogWallets::ThresholdTopUpService).not_to have_received(:call)
    end

    expect(CatalogWallets::ThresholdTopUpService).to have_received(:call).with(wallet:).once
  end

  context "with a void" do
    let(:reason) { "void" }
    let(:invoice) { nil }
    let(:consumptions) { [{inbound_transaction: newer_entry, credit_amount_cents: 4_000}] }

    it "takes the credit out of the entry" do
      expect(result).to be_success
      expect(result.wallet_transaction).to have_attributes(reason: "void", invoice_id: nil, credit_amount_cents: 4_000)
      expect(result.wallet_transaction.fundings.sole).to have_attributes(inbound_transaction_id: newer_entry.id, fee_id: nil, credit_amount_cents: 4_000)
      expect(newer_entry.reload.remaining_credit_amount_cents).to eq(10_000 - 4_000)
      expect(wallet.reload.balance_cents).to eq(15_000 - 4_000)
    end
  end

  shared_examples "a refused debit" do
    it "changes nothing" do
      expect { result }.not_to change {
        [
          wallet.reload.balance_cents,
          older_entry.reload.remaining_credit_amount_cents,
          newer_entry.reload.remaining_credit_amount_cents,
          CatalogWalletTransaction.outbound.count,
          CatalogWalletConsumption.count
        ]
      }

      expect(result).not_to be_success
    end
  end

  context "when the rows ask an entry for more than it has left" do
    let(:consumptions) do
      [
        {inbound_transaction: newer_entry, fee: first_fee, credit_amount_cents: 8_000},
        {inbound_transaction: newer_entry, fee: second_fee, credit_amount_cents: 3_000}
      ]
    end

    it_behaves_like "a refused debit"

    it "fails on the credit amount" do
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq({credit_amount: ["exceeds_remaining_credit"]})
      expect(CatalogWallets::ThresholdTopUpService).not_to have_received(:call)
    end
  end

  context "when the entry lost credit since it was loaded" do
    before do
      described_class.call!(
        wallet: CatalogWallet.find(wallet.id),
        reason: "void",
        consumptions: [{inbound_transaction: CatalogWalletTransaction.find(newer_entry.id), credit_amount_cents: 6_000}]
      )
    end

    it_behaves_like "a refused debit"
  end

  context "when the wallet's balance moved since it was loaded" do
    let(:wallet) { create(:catalog_wallet, organization:, customer:, balance_cents: 19_000) }
    let(:other_entry) { create(:catalog_wallet_transaction, organization:, catalog_wallet: wallet, credit_amount_cents: 4_000) }

    before do
      described_class.call!(
        wallet: CatalogWallet.find(wallet.id),
        reason: "void",
        consumptions: [{inbound_transaction: other_entry, credit_amount_cents: 4_000}]
      )
    end

    it "debits the current balance" do
      expect(result).to be_success
      expect(wallet.reload.balance_cents).to eq(19_000 - 4_000 - 10_000) # balance before - earlier void - this debit
    end
  end

  {pending: :pending, failed: :failed, outbound: :invoice_application}.each do |state, trait|
    context "when an entry is #{state}" do
      let(:newer_entry) { create(:catalog_wallet_transaction, trait, organization:, catalog_wallet: wallet, credit_amount_cents: 10_000) }

      it_behaves_like "a refused debit"

      it "fails with a forbidden error" do
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("wallet_transaction_not_spendable")
      end
    end
  end

  context "when an entry belongs to another wallet" do
    let(:newer_entry) { create(:catalog_wallet_transaction, organization:, credit_amount_cents: 10_000) }

    it_behaves_like "a refused debit"

    it "fails with a forbidden error" do
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("wallet_transaction_not_spendable")
    end
  end

  context "when the reason is not a debit" do
    let(:reason) { "top_up" }

    it "raises" do
      expect { result }.to raise_error(ArgumentError)
    end
  end

  context "without any row" do
    let(:consumptions) { [] }

    it "raises" do
      expect { result }.to raise_error(ArgumentError)
    end
  end

  context "when a row has no positive amount" do
    let(:consumptions) { [{inbound_transaction: newer_entry, fee: first_fee, credit_amount_cents: 0}] }

    it "raises" do
      expect { result }.to raise_error(ArgumentError)
    end
  end

  context "when two rows name the same entry and fee" do
    let(:consumptions) do
      [
        {inbound_transaction: newer_entry, fee: first_fee, credit_amount_cents: 2_000},
        {inbound_transaction: newer_entry, fee: first_fee, credit_amount_cents: 3_000}
      ]
    end

    it "raises" do
      expect { result }.to raise_error(ArgumentError)
    end
  end

  context "when an invoice application has no invoice" do
    let(:invoice) { nil }
    let(:first_fee) { nil }
    let(:second_fee) { nil }

    it "raises" do
      expect { result }.to raise_error(ArgumentError)
    end
  end

  context "when the caller already holds the customer's wallet lock" do
    subject(:result) do
      Customers::LockService.call(customer:, scope: :catalog_wallet, timeout_seconds: 0) do
        described_class.call(wallet:, reason:, consumptions:, invoice:)
      end.value
    end

    before { stub_const("Customers::LockService::ACQUIRE_LOCK_TIMEOUT", 0.seconds) }

    it "debits without waiting" do
      expect(result).to be_success
      expect(wallet.reload.balance_cents).to eq(15_000 - 10_000)
    end
  end

  context "when the customer's wallet lock is held" do
    before { stub_const("Customers::LockService::ACQUIRE_LOCK_TIMEOUT", 0.seconds) }

    around do |test|
      with_advisory_lock("customer-#{customer.id}-catalog_wallet", lock_released_after: 2.seconds) do
        test.run
      end
    end

    it "raises a lock error" do
      expect { result }.to raise_error(BaseLockService::FailedToAcquireLock)
      expect(wallet.reload.balance_cents).to eq(15_000)
    end
  end

  context "with two debits on one entry at the same time", transaction: false do
    subject(:outcomes) do
      wallet_id = wallet.id
      entry_id = newer_entry.id

      with_advisory_lock("customer-#{customer.id}-catalog_wallet", lock_released_after: 1.second) do
        Array.new(2) do
          race do
            described_class.call(
              wallet: CatalogWallet.find(wallet_id),
              reason: "void",
              consumptions: [{inbound_transaction: CatalogWalletTransaction.find(entry_id), credit_amount_cents: 6_000}]
            )
          end
        end.map(&:value)
      end
    end

    let(:wallet) { create(:catalog_wallet, organization:, customer:, balance_cents: 10_000) }

    it "lets one through" do
      expect(outcomes.map(&:success?)).to match_array([true, false])
      expect(newer_entry.reload.remaining_credit_amount_cents).to eq(10_000 - 6_000)
      expect(wallet.reload.balance_cents).to eq(10_000 - 6_000)
    end
  end

  context "with operations on two contracts of one customer", transaction: false do
    subject(:outcomes) do
      pending_entry_id = pending_entry.id
      wallet_id = wallet.id
      entry_id = newer_entry.id
      lock_held = Concurrent::CountDownLatch.new

      settle_side = race do
        ApplicationRecord.transaction do
          CatalogWallets::Ledger::SettleService.call!(wallet_transaction: CatalogWalletTransaction.find(pending_entry_id))
          lock_held.count_down
          sleep(0.5)
          Thread.current[:committing_at] = Time.current
        end
      end
      raise "the settle never took the lock" unless lock_held.wait(5)

      debit_side = race do
        described_class.call(
          wallet: CatalogWallet.find(wallet_id),
          reason: "void",
          consumptions: [{inbound_transaction: CatalogWalletTransaction.find(entry_id), credit_amount_cents: 6_000}]
        )
      end

      [settle_side.tap(&:join)[:committing_at], debit_side.value]
    end

    let(:wallet) { create(:catalog_wallet, organization:, customer:, balance_cents: 10_000) }
    let(:other_wallet) { create(:catalog_wallet, organization:, customer:) }
    let(:pending_entry) do
      create(:catalog_wallet_transaction, :pending, organization:, catalog_wallet: other_wallet, credit_amount_cents: 3_000)
    end

    it "runs them one after the other" do
      settle_committing_at, debit = outcomes

      expect(debit).to be_success
      expect(debit.wallet_transaction.created_at).to be > settle_committing_at
      expect(other_wallet.reload.balance_cents).to eq(3_000)
      expect(wallet.reload.balance_cents).to eq(10_000 - 6_000)
    end
  end
end
