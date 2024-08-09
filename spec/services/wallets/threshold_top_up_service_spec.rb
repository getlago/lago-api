# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::ThresholdTopUpService, type: :service do
  subject(:top_up_service) { described_class.new(wallet:) }

  let(:wallet) do
    create(
      :wallet,
      balance_cents: 1000,
      ongoing_balance_cents: 550,
      ongoing_usage_balance_cents: 450,
      credits_balance: 10.0,
      credits_ongoing_balance: 5.5,
      credits_ongoing_usage_balance: 4.0
    )
  end

  describe "#call" do
    let(:recurring_transaction_rule) do
      create(
        :recurring_transaction_rule,
        wallet:,
        trigger: "threshold",
        threshold_credits: "6.0",
        paid_credits: "10.0",
        granted_credits: "3.0",
        metadata: {'key1' => 'valid_value', 'key2' => 'also_valid'}
      )
    end

    before { recurring_transaction_rule }

    it "calls wallet transaction create job with expected params" do
      expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
        .with(
          organization_id: wallet.organization.id,
          params: {
            wallet_id: wallet.id,
            paid_credits: "10.0",
            granted_credits: "3.0",
            source: :threshold,
            invoice_requires_successful_payment: false,
            metadata: {'key1' => 'valid_value', 'key2' => 'also_valid'}
          }
        )
    end

    context 'when rule requires successful payment' do
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          wallet:,
          trigger: "threshold",
          threshold_credits: "6.0",
          paid_credits: "10.0",
          granted_credits: "3.0",
          invoice_requires_successful_payment: true
        )
      end

      it "calls wallet transaction create job with expected params" do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
          .with(
            organization_id: wallet.organization.id,
            params: hash_including(invoice_requires_successful_payment: true)
          )
      end
    end

    context "when border has NOT been crossed" do
      let(:recurring_transaction_rule) do
        create(:recurring_transaction_rule, wallet:, trigger: "threshold", threshold_credits: "2.0")
      end

      it "does not call wallet transaction create job" do
        expect { top_up_service.call }.not_to have_enqueued_job(WalletTransactions::CreateJob)
      end
    end

    context "with pending transactions" do
      it "does not call wallet transaction create job" do
        create(:wallet_transaction, wallet:, amount: 1.0, credit_amount: 1.0, status: "pending")

        expect { top_up_service.call }.not_to have_enqueued_job(WalletTransactions::CreateJob)
      end
    end

    context "when method is target" do
      let(:recurring_transaction_rule) do
        create(
          :recurring_transaction_rule,
          wallet:,
          trigger: "threshold",
          threshold_credits: "6.0",
          method: "target",
          target_ongoing_balance: "200"
        )
      end

      it "calls wallet transaction create job with expected params" do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
          .with(
            organization_id: wallet.organization.id,
            params: {
              wallet_id: wallet.id,
              paid_credits: "194.5",
              granted_credits: "0.0",
              source: :threshold,
              invoice_requires_successful_payment: false
            }
          )
      end
    end
  end
end
