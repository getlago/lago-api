# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::Balance::DecreaseService, type: :service do
  subject(:create_service) { described_class.new(wallet:, credits_amount:) }

  let(:wallet) { create(:wallet, balance_cents: 1000, credits_balance: 10.0) }
  let(:credits_amount) { BigDecimal('4.5') }

  before { wallet }

  describe '.call' do
    it 'updates wallet balance' do
      expect { create_service.call }
        .to change(wallet.reload, :balance_cents).from(1000).to(550)
        .and change(wallet, :credits_balance).from(10.0).to(5.5)
    end

    it 'updates wallet consumed status' do
      expect { create_service.call }
        .to change(wallet.reload, :consumed_credits).from(0).to(4.5)
        .and change(wallet, :consumed_amount_cents).from(0).to(450)
    end
  end
end
