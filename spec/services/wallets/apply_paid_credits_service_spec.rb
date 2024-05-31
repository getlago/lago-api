# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::ApplyPaidCreditsService, type: :service do
  subject(:service) { described_class.new }

  describe '.call' do
    let(:invoice) { create(:invoice, customer:, organization: customer.organization) }
    let(:customer) { create(:customer) }
    let(:subscription) { create(:subscription, customer:) }
    let(:wallet) { create(:wallet, customer:, balance_cents: 1000, credits_balance: 10.0) }
    let(:wallet_transaction) do
      create(:wallet_transaction, wallet:, amount: 15.0, credit_amount: 15.0, status: 'pending')
    end
    let(:fee) do
      create(
        :fee,
        fee_type: 'credit',
        invoiceable_type: 'WalletTransaction',
        invoiceable_id: wallet_transaction.id,
        invoice:
      )
    end

    before do
      wallet_transaction
      fee
      subscription
      invoice.update(invoice_type: 'credit')
    end

    it 'updates wallet balance' do
      service.call(invoice)

      expect(wallet.reload.balance_cents).to eq 2500
    end

    it 'settles the wallet transaction' do
      service.call(invoice)

      expect(wallet_transaction.reload.status).to eq('settled')
    end
  end
end
