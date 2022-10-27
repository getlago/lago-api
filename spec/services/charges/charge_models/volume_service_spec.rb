# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::VolumeService, type: :service do
  subject(:apply_volume_service) do
    described_class.apply(
      charge: charge,
      aggregation_result: aggregation_result,
      properties: charge.properties,
    )
  end

  before do
    aggregation_result.aggregation = aggregation
  end

  let(:aggregation_result) { BaseService::Result.new }

  let(:charge) do
    create(
      :volume_charge,
      properties: {
        volume_ranges: [
          { from_value: 0, to_value: 100, per_unit_amount: '2', flat_amount: '10' },
          { from_value: 101, to_value: 200, per_unit_amount: '1', flat_amount: '0' },
          { from_value: 201, to_value: nil, per_unit_amount: '0.5', flat_amount: '50' },
        ],
      },
    )
  end

  context 'when aggregation is 0' do
    let(:aggregation) { 0 }

    it 'does not apply the flat amount' do
      expect(apply_volume_service.amount).to eq(0)
    end
  end

  context 'when aggregation is 1' do
    let(:aggregation) { 1 }

    it 'applies a unit amount for 1 and the flat amount' do
      expect(apply_volume_service.amount).to eq(12)
    end
  end

  context 'when aggregation is the limit of the first range' do
    let(:aggregation) { 100 }

    it 'applies unit amount for the first range and the flat amount' do
      expect(apply_volume_service.amount).to eq(210)
    end
  end

  context 'when aggregation is the lower limit of the second range' do
    let(:aggregation) { 101 }

    it 'applies unit amount the second range and no flat amount' do
      expect(apply_volume_service.amount).to eq(101)
    end
  end

  context 'when aggregation is the uper limit of the second range' do
    let(:aggregation) { 200 }

    it 'applies unit amount the second range and no flat amount' do
      expect(apply_volume_service.amount).to eq(200)
    end
  end

  context 'when aggregation is the above the lower limit of the last range' do
    let(:aggregation) { 300 }

    it 'applies unit amount the second range and no flat amount' do
      expect(apply_volume_service.amount).to eq(200)
    end
  end
end
