# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::WalletTransactionFundings::Object do
  subject { described_class }

  it "has the expected fields with correct types" do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:wallet_transaction).of_type("WalletTransaction!")
  end

  describe "#amount_cents" do
    subject { run_graphql_field("WalletTransactionFunding.amountCents", consumption) }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:wallet) { create(:wallet, customer:, traceable: true) }
    let(:inbound_transaction) do
      create(:wallet_transaction,
        wallet:,
        organization:,
        transaction_type: :inbound,
        remaining_amount_cents: 10000)
    end
    let(:outbound_transaction) do
      create(:wallet_transaction, wallet:, organization:, transaction_type: :outbound)
    end
    let(:consumption) do
      create(:wallet_transaction_consumption,
        organization:,
        inbound_wallet_transaction: inbound_transaction,
        outbound_wallet_transaction: outbound_transaction,
        consumed_amount_cents: 5000)
    end

    it "returns the consumed_amount_cents" do
      expect(subject).to eq(5000)
    end
  end
end
