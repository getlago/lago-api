# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::CreateService do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency:) }
  let(:currency) { "EUR" }
  let(:wallet_credit) { WalletCredit.new(wallet:, credit_amount:) }

  let(:wallet) do
    create(
      :wallet,
      customer:,
      currency:,
      balance_cents: 1000,
      credits_balance: 10.0,
      ongoing_balance_cents: 1000,
      credits_ongoing_balance: 10.0
    )
  end

  before do
    wallet
  end

  describe "#call" do
    subject(:result) { described_class.call(wallet:, wallet_credit:, **transaction_params) }

    context "with minimum arguments" do
      let(:credit_amount) { 100 }

      let(:transaction_params) do
        {
          status: :pending,
          transaction_type: :inbound,
          transaction_status: :purchased
        }
      end

      it "creates a wallet transaction" do
        expect { subject }.to change(WalletTransaction, :count).by(1)
      end

      it "sets default values" do
        expect(result.wallet_transaction)
          .to be_a(WalletTransaction)
          .and be_persisted
          .and have_attributes(
            invoice_requires_successful_payment: false,
            metadata: [],
            priority: 50,
            source: "manual"
          )
      end
    end

    context "with all arguments" do
      let(:credit_amount) { 1000 }
      let(:credit_note) { create(:credit_note) }
      let(:invoice) { create(:invoice) }

      let(:transaction_params) do
        {
          status: :pending,
          transaction_type: :outbound,
          transaction_status: :granted,
          source: :threshold,
          metadata: [{key: "value"}],
          invoice_requires_successful_payment: true,
          settled_at: Date.yesterday,
          credit_note_id: credit_note.id,
          invoice_id: invoice.id,
          priority: 25,
          name: "Custom Transaction Name"
        }
      end

      it "creates a wallet transaction" do
        expect { subject }.to change(WalletTransaction, :count).by(1)
      end

      it "sets all attributes" do
        wallet_transaction = result.wallet_transaction

        expect(wallet_transaction.status).to eq("pending")
        expect(wallet_transaction.transaction_type).to eq("outbound")
        expect(wallet_transaction.transaction_status).to eq("granted")
        expect(wallet_transaction.source).to eq("threshold")
        expect(wallet_transaction.metadata).to eq([{"key" => "value"}])
        expect(wallet_transaction.invoice_requires_successful_payment).to be true
        expect(wallet_transaction.settled_at).to eq(Date.yesterday)
        expect(wallet_transaction.credit_note_id).to eq(credit_note.id)
        expect(wallet_transaction.invoice_id).to eq(invoice.id)
        expect(wallet_transaction.credit_amount).to eq(credit_amount)
        expect(wallet_transaction.priority).to eq 25
        expect(wallet_transaction.name).to eq("Custom Transaction Name")
      end
    end
  end
end
