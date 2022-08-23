# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::Balance::DecreaseService, type: :service do
  subject(:create_service) { described_class.new(wallet: wallet, credits_amount: credits_amount) }

  let(:wallet) { create(:wallet, balance: '10.00', credits_balance: '10.00') }
  let(:credits_amount) { BigDecimal('4.5') }

  before { wallet }

  describe '.call' do
    it 'updates wallet balance' do
      create_service.call

      expect(wallet.reload.balance).to eq('5.5')
      expect(wallet.reload.credits_balance).to eq('5.5')
    end

    it 'updates wallet consumed status' do
      create_service.call

      expect(wallet.reload.consumed_credits).to eq('4.5')
    end
  end
end
