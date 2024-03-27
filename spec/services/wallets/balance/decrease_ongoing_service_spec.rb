# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::Balance::DecreaseOngoingService, type: :service do
  subject(:decrease_service) { described_class.new(wallet:, credits_amount:) }

  let(:wallet) do
    create(
      :wallet,
      balance_cents: 1000,
      ongoing_balance_cents: 800,
      ongoing_usage_balance_cents: 200,
      credits_balance: 10.0,
      credits_ongoing_balance: 8.0,
      credits_ongoing_usage_balance: 2.0
    )
  end
  let(:credits_amount) { BigDecimal("4.5") }

  before { wallet }

  describe ".call" do
    it "updates wallet balance" do
      expect { decrease_service.call }
        .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(450)
        .and change(wallet, :credits_ongoing_usage_balance).from(2.0).to(4.5)
        .and change(wallet, :ongoing_balance_cents).from(800).to(550)
        .and change(wallet, :credits_ongoing_balance).from(8.0).to(5.5)
    end

    context "with recurring transaction threshold rule" do
      let(:recurring_transaction_rule) do
        create(:recurring_transaction_rule, wallet:, rule_type: "threshold", threshold_credits: "6.0")
      end

      before { recurring_transaction_rule }

      it "calls wallet transaction create job when threshold border has been crossed" do
        expect { decrease_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
      end

      context "when border has NOT been crossed" do
        let(:recurring_transaction_rule) do
          create(:recurring_transaction_rule, wallet:, rule_type: "threshold", threshold_credits: "2.0")
        end

        it "does not call wallet transaction create job" do
          expect { decrease_service.call }.not_to have_enqueued_job(WalletTransactions::CreateJob)
        end
      end

      context "without any usage" do
        let(:wallet) do
          create(
            :wallet,
            balance_cents: 200,
            ongoing_balance_cents: 200,
            ongoing_usage_balance_cents: 0,
            credits_balance: 2.0,
            credits_ongoing_balance: 2.0,
            credits_ongoing_usage_balance: 0.0
          )
        end
        let(:credits_amount) { BigDecimal("0.0") }

        it "calls wallet transaction create job" do
          expect { decrease_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
        end
      end
    end
  end
end
