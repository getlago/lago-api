# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::PrepaidCreditJob do
  let(:invoice) { create(:invoice, customer:, organization: customer.organization) }
  let(:customer) { create(:customer) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:, balance_cents: 1000, credits_balance: 10.0) }
  let(:wallet_transaction) do
    create(:wallet_transaction, wallet:, amount: 15.0, credit_amount: 15.0, status: "pending")
  end
  let(:fee) do
    create(
      :fee,
      fee_type: "credit",
      invoiceable_type: "WalletTransaction",
      invoiceable_id: wallet_transaction.id,
      invoice:
    )
  end

  before do
    wallet_transaction
    fee
    subscription
    invoice.update(invoice_type: "credit")
  end

  it "updates wallet balance" do
    described_class.perform_now(invoice)

    expect(wallet.reload.balance_cents).to eq(2500)
  end

  it "settles the wallet transaction" do
    described_class.perform_now(invoice)

    expect(wallet_transaction.reload.status).to eq("settled")
  end

  it "finalize the invoice" do
    allow(Invoices::FinalizeOpenCreditService).to receive(:call)
    described_class.perform_now(invoice)
    expect(Invoices::FinalizeOpenCreditService).to have_received(:call).with(invoice:)
  end

  it "does not retry the job" do
    expect {
      described_class.perform_now(invoice)
    }.not_to have_enqueued_job(described_class)
  end

  context "when there is race condition error" do
    before do
      allow(Wallets::ApplyPaidCreditsService).to receive(:call).and_raise(ActiveRecord::StaleObjectError.new)
    end

    it "retries the job" do
      expect {
        described_class.perform_now(invoice)
      }.to have_enqueued_job(described_class)
    end
  end

  context "when payment fails" do
    it "marks the wallet transaction as failed" do
      allow(WalletTransactions::MarkAsFailedService).to receive(:new).and_call_original
      described_class.perform_now(invoice, :failed)
      expect(WalletTransactions::MarkAsFailedService).to have_received(:new).with(wallet_transaction: wallet_transaction)
      expect(wallet_transaction.reload.status).to eq("failed")
    end
  end
end
