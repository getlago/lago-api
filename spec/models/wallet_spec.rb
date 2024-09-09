# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallet, type: :model do
  subject(:wallet) { build(:wallet) }

  describe 'validations' do
    it { is_expected.to validate_numericality_of(:rate_amount).is_greater_than(0) }
  end

  describe 'currency=' do
    it 'assigns the currency to all amounts' do
      wallet.currency = 'CAD'

      expect(wallet).to have_attributes(
        balance_currency: 'CAD',
        consumed_amount_currency: 'CAD'
      )
    end
  end

  describe 'currency' do
    it 'returns the wallet currency' do
      expect(wallet.currency).to eq(wallet.balance_currency)
    end
  end
end
