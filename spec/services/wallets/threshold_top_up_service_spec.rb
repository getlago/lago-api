# frozen_string_literal: true

require 'rails_helper'

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
      credits_ongoing_usage_balance: 4.0,
    )
  end

  describe '#call' do
    let(:recurring_transaction_rule) do
      create(:recurring_transaction_rule, wallet:, trigger: 'threshold', threshold_credits: '6.0')
    end

    before { recurring_transaction_rule }

    it 'calls wallet transaction create job when threshold border has been crossed' do
      expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
    end

    context 'when border has NOT been crossed' do
      let(:recurring_transaction_rule) do
        create(:recurring_transaction_rule, wallet:, trigger: 'threshold', threshold_credits: '2.0')
      end

      it 'does not call wallet transaction create job' do
        expect { top_up_service.call }.not_to have_enqueued_job(WalletTransactions::CreateJob)
      end
    end

    context 'with pending transactions' do
      it 'does not call wallet transaction create job' do
        create(:wallet_transaction, wallet:, amount: 1.0, credit_amount: 1.0, status: 'pending')
        expect { top_up_service.call }.not_to have_enqueued_job(WalletTransactions::CreateJob)
      end
    end

    context 'without any usage' do
      let(:wallet) do
        create(
          :wallet,
          balance_cents: 200,
          ongoing_balance_cents: 200,
          ongoing_usage_balance_cents: 0,
          credits_balance: 2.0,
          credits_ongoing_balance: 2.0,
          credits_ongoing_usage_balance: 0.0,
        )
      end
      let(:credits_amount) { BigDecimal('0.0') }

      it 'calls wallet transaction create job' do
        expect { top_up_service.call }.to have_enqueued_job(WalletTransactions::CreateJob)
      end
    end
  end
end
