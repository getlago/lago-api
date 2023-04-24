# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WalletTransactions::SettleService, type: :service do
  subject(:service) { described_class.new(wallet_transaction:) }

  let(:wallet_transaction) { create(:wallet_transaction, status: 'pending', settled_at: nil) }

  describe '.call' do
    it 'updates wallet_transaction status' do
      expect {
        service.call
      }.to change { wallet_transaction.reload.status }.from('pending').to('settled')
        .and change(wallet_transaction, :settled_at).from(nil)
    end
  end
end
