# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::PercentageService, type: :service do
  subject(:percentage_service) { described_class.new(charge: charge) }

  let(:charge) do
    create(
      :percentage_charge,
      properties: {
        rate: '0.0555',
        fixed_amount_value: '0',
        fixed_amount_target: 'each_unit',
      },
    )
  end

  context 'when fixed amount value is zero' do
    it 'applies the percentage rate to the value' do
      expect(percentage_service.apply(value: 100).amount).to eq(5.55)
    end
  end

  context 'when fixed amount value is NOT zero and should be applied on each unit' do
    let(:charge) do
      create(
        :percentage_charge,
        properties: {
          rate: '0.0555',
          fixed_amount_value: '2',
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
          rate: '0.0555',
          fixed_amount_value: '2',
          fixed_amount_target: 'all_units',
        },
      )
    end

    it 'applies the percentage rate and the additional charge on all inits' do
      expect(percentage_service.apply(value: 100).amount).to eq(7.55)
    end
  end
end
