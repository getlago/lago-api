# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::CreateFromParamsService, type: :service do
  subject(:create_service) { described_class.call(organization:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:, currency:) }
  let(:currency) { "EUR" }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) do
    create(
      :wallet,
      customer:,
      currency:,
      rate_amount:,
      balance_cents: 1000,
      credits_balance: 10.0,
      ongoing_balance_cents: 1000,
      credits_ongoing_balance: 10.0
    )
  end
  let(:rate_amount) { 1 }

  before do
    allow(Utils::ActivityLog).to receive(:produce)

    subscription
  end

  describe "#call" do
    let(:paid_credits) { "10.00" }
    let(:granted_credits) { "15.00" }
    let(:voided_credits) { "3.00" }
    let(:params) do
      {
        wallet_id: wallet.id,
        paid_credits:,
        granted_credits:,
        voided_credits:,
        source: :manual
      }
    end

    it "creates wallet transactions" do
      expect { create_service }.to change(WalletTransaction, :count).by(3)
    end

    it "sets expected transaction status", :aggregate_failures do
      create_service
      transactions = WalletTransaction.where(wallet_id: wallet.id)

      expect(transactions.purchased.first.credit_amount).to eq(10)
      expect(transactions.granted.first.credit_amount).to eq(15)
      expect(transactions.voided.first.credit_amount).to eq(3)
    end

    it "sets expected source" do
      create_service
      expect(WalletTransaction.where(wallet_id: wallet.id).pluck(:source).uniq).to eq(["manual"])
    end

    it "enqueues the BillPaidCreditJob" do
      expect { create_service }.to have_enqueued_job(BillPaidCreditJob)
    end

    it "updates wallet balance based on granted and voided credits" do
      create_service

      expect(wallet.reload.balance_cents).to eq(2200)
      expect(wallet.reload.credits_balance).to eq(22.0)
    end

    it "updates wallet ongoing balance based on granted and voided credits" do
      create_service

      expect(wallet.reload.ongoing_balance_cents).to eq(2200)
      expect(wallet.reload.credits_ongoing_balance).to eq(22.0)
    end

    it "enqueues a SendWebhookJob for each wallet transaction" do
      expect do
        create_service
      end.to have_enqueued_job(SendWebhookJob).thrice.with("wallet_transaction.created", WalletTransaction)
    end

    it "produces an activity log" do
      create_service

      expect(Utils::ActivityLog).to have_received(:produce).thrice.with(an_instance_of(WalletTransaction), "wallet_transaction.created")
    end

    context "with valid metadata" do
      let(:metadata) { [{"key" => "valid_value", "value" => "also_valid"}] }
      let(:params) do
        {
          wallet_id: wallet.id,
          paid_credits:,
          granted_credits:,
          voided_credits:,
          source: :manual,
          metadata: metadata
        }
      end

      it "processes the transaction normally and includes the metadata" do
        expect(create_service).to be_success
        transactions = WalletTransaction.where(wallet_id: wallet.id)
        expect(transactions.first.metadata).to include("key" => "valid_value", "value" => "also_valid")
        expect(transactions.second.metadata).to include("key" => "valid_value", "value" => "also_valid")
        expect(transactions.third.metadata).to include("key" => "valid_value", "value" => "also_valid")
      end
    end

    context "with validation error" do
      let(:paid_credits) { "-15.00" }

      it "returns an error" do
        result = create_service

        expect(result).not_to be_success
        expect(result.error.messages[:paid_credits]).to eq(["invalid_paid_credits"])
      end
    end

    context "with decimal value" do
      let(:paid_credits) { "4.399999" }

      it "creates wallet transaction with rounded value" do
        result = create_service
        expect(result.wallet_transactions.first.credit_amount).to eq(4.40)
        expect(result.wallet_transactions.first.amount).to eq(4.40)
      end
    end

    context "with decimal value and small rate amount" do
      let(:paid_credits) { "4.399999" }
      let(:rate_amount) { 0.01 }

      it "creates wallet transaction with rounded value" do
        result = create_service
        expect(result.wallet_transactions.first.credit_amount).to eq(4)
        expect(result.wallet_transactions.first.amount).to eq(0.04)
      end
    end

    context "with decimal value and large rate amount" do
      let(:paid_credits) { "4.3789" }
      let(:rate_amount) { 100 }

      it "creates wallet transaction with rounded value" do
        result = create_service
        expect(result.wallet_transactions.first.credit_amount).to eq(4.3789)
        expect(result.wallet_transactions.first.amount).to eq(437.89)
      end
    end

    context "with decimal value and currency without digits" do
      let(:paid_credits) { "4.39999" }
      let(:currency) { "JPY" }

      it "creates wallet transaction with rounded value" do
        result = create_service
        expect(result.wallet_transactions.first.credit_amount).to eq(4)
        expect(result.wallet_transactions.first.amount).to eq(4)
      end
    end
  end
end
