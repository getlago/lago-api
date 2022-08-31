# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::Balance::DecreaseService, type: :service do
  subject(:create_service) { described_class.new(wallet: wallet, credits_amount: credits_amount) }

  let(:wallet) { create(:wallet, balance: 10.0, credits_balance: 10.0) }
  let(:credits_amount) { BigDecimal('4.5') }

  before { wallet }

  describe '.call' do
    it 'updates wallet balance' do
      expect {
        create_service.call
      }.to change { wallet.reload.balance }.from(10.0).to(5.5)
      .and change { wallet.credits_balance }.from(10.0).to(5.5)
    end

    it 'updates wallet consumed status' do
      expect {
        create_service.call
      }.to change { wallet.reload.consumed_credits }.from(0.0).to(4.5)
      .and change { wallet.consumed_amount }.from(0.0).to(4.5)
    end
  end
end
