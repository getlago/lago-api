# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WalletTransactions::CreateService, type: :service do
  subject(:create_service) { described_class.call(organization:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) do
    create(
      :wallet,
      customer:,
      balance_cents: 1000,
      credits_balance: 10.0,
      ongoing_balance_cents: 1000,
      credits_ongoing_balance: 10.0,
    )
  end

  before do
    subscription
  end

  describe '#call' do
    let(:paid_credits) { '10.00' }
    let(:granted_credits) { '15.00' }
    let(:params) do
      {
        wallet_id: wallet.id,
        paid_credits:,
        granted_credits:,
        source: :manual,
      }
    end

    it 'creates a wallet transactions' do
      expect { create_service }.to change(WalletTransaction, :count).by(2)
    end

    it 'sets expected transaction status', :aggregate_failures do
      create_service
      paid_transaction = WalletTransaction.where(wallet_id: wallet.id).paid.first
      offered_transaction = WalletTransaction.where(wallet_id: wallet.id).offered.first

      expect(paid_transaction.credit_amount).to eq(10)
      expect(offered_transaction.credit_amount).to eq(15)
    end

    it 'sets correct source' do
      create_service
      wallet_transactions = WalletTransaction.where(wallet_id: wallet.id).order(created_at: :desc)

      aggregate_failures do
        expect(wallet_transactions[0].source.to_s).to eq('manual')
        expect(wallet_transactions[1].source.to_s).to eq('manual')
      end
    end

    it 'enqueues the BillPaidCreditJob' do
      expect { create_service }.to have_enqueued_job(BillPaidCreditJob)
    end

    it 'updates wallet balance only with granted credits' do
      create_service

      expect(wallet.reload.balance_cents).to eq(2500)
      expect(wallet.reload.credits_balance).to eq(25.0)
    end

    it 'updates wallet ongoing balance only with granted credits' do
      create_service

      expect(wallet.reload.ongoing_balance_cents).to eq(2500)
      expect(wallet.reload.credits_ongoing_balance).to eq(25.0)
    end

    it 'enqueues a SendWebhookJob for each wallet transaction' do
      expect do
        create_service.call
      end.to have_enqueued_job(SendWebhookJob).twice.with('wallet_transaction.created', WalletTransaction)
    end

    context 'with validation error' do
      let(:paid_credits) { '-15.00' }

      it 'returns an error' do
        result = create_service

        expect(result).not_to be_success
        expect(result.error.messages[:paid_credits]).to eq(['invalid_paid_credits'])
      end
    end
  end
end
