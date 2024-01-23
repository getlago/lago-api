# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::Balance::IncreaseOngoingService, type: :service do
  subject(:create_service) { described_class.new(wallet:, credits_amount:) }

  let(:credits_amount) { BigDecimal('4.5') }
  let(:wallet) do
    create(
      :wallet,
      balance_cents: 1000,
      ongoing_balance_cents: 800,
      credits_balance: 10.0,
      credits_ongoing_balance: 8.0,
    )
  end

  before { wallet }

  describe '.call' do
    it 'updates wallet ongoing balance' do
      expect { create_service.call }
        .to change(wallet, :ongoing_balance_cents).from(800).to(1250)
        .and change(wallet, :credits_ongoing_balance).from(8.0).to(12.5)
    end
  end
end
