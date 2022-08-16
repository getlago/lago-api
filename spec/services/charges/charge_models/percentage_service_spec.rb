# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::PercentageService, type: :service do
  subject(:percentage_service) { described_class.new(charge: charge) }

  let(:charge) do
    create(
      :percentage_charge,
      properties: {
        rate: '5.55',
        fixed_amount: '0',
      },
    )
  end

  context 'when fixed amount value is zero' do
    it 'applies the percentage rate to the value' do
      expect(percentage_service.apply(value: 100).amount).to eq(5.55)
    end
  end

  context 'when fixed amount value is nil and fixed amount target is nil' do
    let(:charge) do
      create(
        :percentage_charge,
        properties: {
          rate: '5.55',
          fixed_amount: nil,
        },
      )
    end

    it 'applies the percentage rate to the value' do
      expect(percentage_service.apply(value: 100).amount).to eq(5.55)
    end
  end

  context 'when fixed amount value is NOT zero' do
    let(:charge) do
      create(
        :percentage_charge,
        properties: {
          rate: '5.55',
          fixed_amount: '2',
        },
      )
    end

    it 'applies the percentage rate and the additional charge on each unit' do
      expect(percentage_service.apply(value: 100).amount).to eq(205.55)
    end
  end
end
