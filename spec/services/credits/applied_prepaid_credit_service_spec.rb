# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Credits::AppliedPrepaidCreditService do
  subject(:credit_service) { described_class.new(invoice:, wallet:) }

  let(:invoice) do
    create(
      :invoice,
      customer:,
      currency: 'EUR',
      total_amount_cents: amount_cents,
    )
  end
  let(:amount_cents) { 100 }
  let(:wallet) { create(:wallet, customer:, balance_cents: 1000, credits_balance: 10.0) }
  let(:customer) { create(:customer) }
  let(:subscription) { create(:subscription, customer:) }

  before { subscription }

  describe '#call' do
    it 'calculates prepaid credit' do
      result = credit_service.call

      expect(result).to be_success
      expect(result.prepaid_credit_amount_cents).to eq(100)
      expect(invoice.prepaid_credit_amount_cents).to eq(100)
    end

    it 'creates wallet transaction' do
      result = credit_service.call

      expect(result).to be_success
      expect(result.wallet_transaction).to be_present
      expect(result.wallet_transaction.amount).to eq(1.0)
      expect(result.wallet_transaction).to be_paid
    end

    it 'updates wallet balance' do
      result = credit_service.call
      wallet = result.wallet_transaction.wallet

      expect(wallet.balance_cents).to eq(900)
      expect(wallet.credits_balance).to eq(9.0)
    end

    it 'enqueues a SendWebhookJob' do
      expect { credit_service.call }.to have_enqueued_job(SendWebhookJob)
        .with('wallet_transaction.created', WalletTransaction)
    end

    context 'when wallet credits are less than invoice amount' do
      let(:amount_cents) { 1500 }

      it 'calculates prepaid credit' do
        result = credit_service.call

        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(1000)
      end

      it 'creates wallet transaction' do
        result = credit_service.call

        expect(result).to be_success
        expect(result.wallet_transaction).to be_present
        expect(result.wallet_transaction.amount).to eq(10.0)
      end

      it 'updates wallet balance' do
        result = credit_service.call
        wallet = result.wallet_transaction.wallet

        expect(wallet.balance).to eq(0.0)
        expect(wallet.credits_balance).to eq(0.0)
      end
    end
  end
end
