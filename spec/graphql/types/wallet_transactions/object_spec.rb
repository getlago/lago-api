# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::WalletTransactions::Object do
  subject { described_class }

  it "has the expected fields with correct types" do
    expect(subject).to have_field(:wallet).of_type("Wallet")

    expect(subject).to have_field(:amount).of_type("String!")
    expect(subject).to have_field(:credit_amount).of_type("String!")
    expect(subject).to have_field(:invoice_requires_successful_payment).of_type("Boolean!")
    expect(subject).to have_field(:name).of_type("String")
    expect(subject).to have_field(:priority).of_type("Int!")
    expect(subject).to have_field(:source).of_type("WalletTransactionSourceEnum!")
    expect(subject).to have_field(:status).of_type("WalletTransactionStatusEnum!")
    expect(subject).to have_field(:transaction_status).of_type("WalletTransactionTransactionStatusEnum!")
    expect(subject).to have_field(:transaction_type).of_type("WalletTransactionTransactionTypeEnum!")
    expect(subject).to have_field(:wallet_name).of_type("String")

    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:failed_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:invoice).of_type("Invoice")
    expect(subject).to have_field(:metadata).of_type("[WalletTransactionMetadataObject!]")
    expect(subject).to have_field(:settled_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")
  end

  describe "#wallet_name" do
    subject { run_graphql_field("WalletTransaction.walletName", wallet_transaction) }

    let(:wallet_transaction) { create(:wallet_transaction) }

    context "when wallet has a name" do
      it "returns the wallet name" do
        expect(subject).to be_present
        expect(subject).to eq(wallet_transaction.wallet.name)
      end
    end

    context "when wallet has no name" do
      let(:wallet_transaction) { create(:wallet_transaction, wallet: create(:wallet, name: nil)) }

      it "returns nil" do
        expect(subject).to be_nil
      end
    end
  end
end
