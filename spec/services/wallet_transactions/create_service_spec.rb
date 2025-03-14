# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::CreateService, type: :service do
  subject(:create_service) do
    described_class.call(wallet:,
      wallet_credit:,
      status:,
      transaction_type:,
      from_source:,
      metadata:,
      transaction_status:,
      invoice_requires_successful_payment:,
      settled_at:,
      credit_note_id:,
      invoice_id:)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency:) }
  let(:currency) { "EUR" }
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
  let(:status) { :pending }
  let(:transaction_type) { :inbound }
  let(:transaction_status) { :purchased }
  let(:from_source) { :manual }
  let(:metadata) { [] }
  let(:invoice_requires_successful_payment) { false }
  let(:settled_at) { nil }
  let(:credit_note_id) { nil }
  let(:invoice_id) { nil }
  let(:wallet_credit) { WalletCredit.new(wallet:, credit_amount:) }
  let(:credit_amount) { 100 }

  before do
    wallet
  end

  describe "#call" do
    it "creates a wallet transaction" do
      expect { create_service }.to change(WalletTransaction, :count).by(1)
    end
  end

  context "with non-default arguments" do
    let(:status) { :pending }
    let(:transaction_type) { :outbound }
    let(:transaction_status) { :granted }
    let(:from_source) { :threshold }
    let(:metadata) { [{key: "value"}] }
    let(:invoice_requires_successful_payment) { true }
    let(:settled_at) { Date.yesterday }
    let(:credit_note) { create(:credit_note) }
    let(:credit_note_id) { credit_note.id }
    let(:invoice) { create(:invoice) }
    let(:invoice_id) { invoice.id }
    let(:wallet_credit) { WalletCredit.new(wallet:, credit_amount:) }
    let(:credit_amount) { 1000 }

    describe "#call" do
      it "creates a wallet transaction and sets all attributes" do
        wallet_transaction = create_service.wallet_transaction

        expect(wallet_transaction.status).to eq("pending")
        expect(wallet_transaction.transaction_type).to eq("outbound")
        expect(wallet_transaction.transaction_status).to eq("granted")
        expect(wallet_transaction.source).to eq("threshold")
        expect(wallet_transaction.metadata).to eq([{"key" => "value"}])
        expect(wallet_transaction.invoice_requires_successful_payment).to be_truthy
        expect(wallet_transaction.settled_at).to eq(Date.yesterday)
        expect(wallet_transaction.credit_note_id).to eq(credit_note_id)
        expect(wallet_transaction.invoice_id).to eq(invoice_id)
        expect(wallet_transaction.credit_amount).to eq(credit_amount)
      end
    end
  end
end
