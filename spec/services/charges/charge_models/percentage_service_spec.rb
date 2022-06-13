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
        fixed_amount_target: 'each_unit',
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
          fixed_amount_target: nil,
        },
      )
    end

    it 'applies the percentage rate to the value' do
      expect(percentage_service.apply(value: 100).amount).to eq(5.55)
    end
  end

  context 'when fixed amount value is NOT zero and should be applied on each unit' do
    let(:charge) do
      create(
        :percentage_charge,
        properties: {
          rate: '5.55',
          fixed_amount: '2',
          fixed_amount_target: 'each_unit',
        },
      )
    end

    it 'applies the percentage rate and the additional charge on each init' do
      expect(percentage_service.apply(value: 100).amount).to eq(205.55)
    end
  end

  context 'when fixed amount value is NOT zero and should be applied on all units' do
    let(:charge) do
      create(
        :percentage_charge,
        properties: {
          rate: '5.5555',
          fixed_amount: '2',
          fixed_amount_target: 'all_units',
        },
      )
    end

    it 'applies the percentage rate and the additional charge on all inits' do
      expect(percentage_service.apply(value: 100).amount).to eq(7.5555)
    end

    context 'with value equal to zero' do
      it 'applies the percentage rate and the additional charge on all inits' do
        expect(percentage_service.apply(value: 0).amount).to eq(0)
      end
    end
  end
end
