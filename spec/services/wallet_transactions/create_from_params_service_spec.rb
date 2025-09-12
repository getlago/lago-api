# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::CreateFromParamsService, type: :service do
  let(:organization) { create(:organization) }
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
    subscription
  end

  describe "#call" do
    subject(:result) { described_class.call(organization:, params:) }

    let(:paid_credits) { "10.00" }
    let(:granted_credits) { "15.00" }
    let(:voided_credits) { "3.00" }
    let(:params) do
      {
        wallet_id: wallet.id,
        paid_credits:,
        granted_credits:,
        voided_credits:,
        **((name == :undefined) ? {} : {name:})
      }
    end
    let(:name) { :undefined }

    it "creates wallet transactions" do
      expect { subject }.to change(WalletTransaction, :count).by(3)
    end

    it "defaults priority to 50, name to nil and source to manual" do
      expect(result.wallet_transactions).to all(have_attributes(priority: 50, name: nil, source: "manual"))
      expect(WalletTransaction.where(wallet_id: wallet.id)).to all(have_attributes(priority: 50, name: nil, source: "manual"))
    end

    it "sets expected transaction status" do
      subject
      transactions = WalletTransaction.where(wallet_id: wallet.id)

      expect(transactions.find(&:purchased?).credit_amount).to eq(10)
      expect(transactions.find(&:granted?).credit_amount).to eq(15)
      expect(transactions.find(&:voided?).credit_amount).to eq(3)
    end

    it "enqueues the BillPaidCreditJob" do
      expect { subject }.to have_enqueued_job_after_commit(BillPaidCreditJob)
    end

    it "updates wallet balance based on granted and voided credits" do
      subject

      expect(wallet.reload.balance_cents).to eq(2200)
      expect(wallet.reload.credits_balance).to eq(22.0)
    end

    it "updates wallet ongoing balance based on granted and voided credits" do
      subject

      expect(wallet.reload.ongoing_balance_cents).to eq(2200)
      expect(wallet.reload.credits_ongoing_balance).to eq(22.0)
    end

    it "enqueues a SendWebhookJob for each wallet transaction" do
      expect do
        subject
      end.to have_enqueued_job(SendWebhookJob).thrice.with("wallet_transaction.created", WalletTransaction)
    end

    it "produces an activity log" do
      subject

      expect(Utils::ActivityLog).to have_received(:produce).thrice.with(an_instance_of(WalletTransaction), "wallet_transaction.created")
    end

    context "with metadata parameter" do
      let(:metadata) { [{"key" => "valid_value", "value" => "also_valid"}] }
      let(:params) do
        {
          wallet_id: wallet.id,
          paid_credits:,
          granted_credits:,
          voided_credits:,
          metadata: metadata
        }.with_indifferent_access
      end

      it "processes the transaction normally and includes the metadata" do
        expect(result).to be_success
        transactions = WalletTransaction.where(wallet_id: wallet.id)
        expect(transactions).to all(have_attributes(metadata: [{"key" => "valid_value", "value" => "also_valid"}]))
      end
    end

    context "with priority parameter" do
      let(:params) do
        {
          wallet_id: wallet.id,
          paid_credits:,
          granted_credits:,
          voided_credits:,
          priority:
        }
      end

      let(:priority) { 25 }

      it "creates wallet transactions with specified priority" do
        expect(result.wallet_transactions).to all(have_attributes(priority:))
      end
    end

    context "with source parameter" do
      let(:params) do
        {
          wallet_id: wallet.id,
          paid_credits:,
          granted_credits:,
          voided_credits:,
          source: :interval
        }
      end

      it "creates wallet transactions with specified source" do
        expect(result.wallet_transactions).to all(have_attributes(source: "interval"))
      end
    end

    context "with name parameter" do
      let(:name) { "Custom Top-up Name" }

      it "creates wallet transactions with specified name" do
        expect(result.wallet_transactions).to all(have_attributes(name: "Custom Top-up Name"))
      end

      context "when name parameter is blank" do
        let(:name) { "" }

        it "creates wallet transactions with nil name" do
          expect(result.wallet_transactions).to all(have_attributes(name: nil))
        end
      end

      context "when name parameter is nil" do
        let(:name) { nil }

        it "creates wallet transactions with nil name" do
          expect(result.wallet_transactions).to all(have_attributes(name: nil))
        end
      end
    end

    context "with validation error" do
      let(:paid_credits) { "-15.00" }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.messages[:paid_credits]).to eq(["invalid_paid_credits", "invalid_amount"])
      end

      context "when paid_credits is below the wallet minimum" do
        let(:paid_credits) { "5.00" }

        before { wallet.update! paid_top_up_min_amount_cents: 100_00 }

        it "returns an error" do
          expect(result).not_to be_success
          expect(result.error.messages[:paid_credits]).to eq(["amount_below_minimum"])
        end

        context "when ignore_paid_top_up_limits is true" do
          let(:params) do
            {
              wallet_id: wallet.id,
              paid_credits:,
              ignore_paid_top_up_limits: true
            }
          end

          it "creates wallet transaction" do
            expect(result).to be_success
            expect(result.wallet_transactions.first.credit_amount).to eq(5)
          end
        end
      end
    end

    context "with decimal value" do
      let(:paid_credits) { "4.399999" }

      it "creates wallet transaction with rounded value" do
        expect(result.wallet_transactions.first.credit_amount).to eq(4.40)
        expect(result.wallet_transactions.first.amount).to eq(4.40)
      end
    end

    context "with decimal value and small rate amount" do
      let(:paid_credits) { "4.399999" }
      let(:rate_amount) { 0.01 }

      it "creates wallet transaction with rounded value" do
        expect(result.wallet_transactions.first.credit_amount).to eq(4)
        expect(result.wallet_transactions.first.amount).to eq(0.04)
      end
    end

    context "with decimal value and large rate amount" do
      let(:paid_credits) { "4.3789" }
      let(:rate_amount) { 100 }

      it "creates wallet transaction with rounded value" do
        expect(result.wallet_transactions.first.credit_amount).to eq(4.3789)
        expect(result.wallet_transactions.first.amount).to eq(437.89)
      end
    end

    context "with decimal value and currency without digits" do
      let(:paid_credits) { "4.39999" }
      let(:currency) { "JPY" }

      it "creates wallet transaction with rounded value" do
        expect(result.wallet_transactions.first.credit_amount).to eq(4)
        expect(result.wallet_transactions.first.amount).to eq(4)
      end
    end
  end
end
