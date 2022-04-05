# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fee, type: :model do
  subject(:fee_model) { described_class }

  describe '.subscription_fee?' do
    it 'checks non presence of charge' do
      expect(fee_model.new.subscription_fee?).to be_truthy
    end
  end

  describe '.charge_fee?' do
    it 'checks presence of charge' do
      expect(fee_model.new(charge_id: SecureRandom.uuid).charge_fee?).to be_truthy
    end
  end

  describe '.compute_vat' do
    it 'computes the vat' do
      fee = fee_model.new(amount_cents: 100, amount_currency: 'EUR', vat_rate: 20.0)

      fee.compute_vat

      aggregate_failures do
        expect(fee.vat_amount_currency).to eq('EUR')
        expect(fee.vat_amount_cents).to eq(20)
      end
    end
  end
end
