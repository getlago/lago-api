# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::Balance::IncreaseService, type: :service do
  subject(:create_service) { described_class.new(wallet:, credits_amount:) }

  let(:wallet) { create(:wallet, balance_cents: 1000, credits_balance: 10.0) }
  let(:credits_amount) { BigDecimal('4.5') }

  before { wallet }

  describe '.call' do
    it 'updates wallet balance' do
      expect { create_service.call }
        .to change(wallet.reload, :balance_cents).from(1000).to(1450)
        .and change(wallet, :credits_balance).from(10.0).to(14.5)
    end
  end
end
