# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::GraduatedService, type: :service do
  subject(:apply_graduated_service) do
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
      :graduated_charge,
      properties: {
        graduated_ranges: [
          {
            from_value: 0,
            to_value: 10,
            per_unit_amount: '10',
            flat_amount: '2',
          },
          {
            from_value: 11,
            to_value: 20,
            per_unit_amount: '5',
            flat_amount: '3',
          },
          {
            from_value: 21,
            to_value: nil,
            per_unit_amount: '5',
            flat_amount: '3',
          },
        ],
      },
    )
  end

  context 'when aggregation is 0' do
    let(:aggregation) { 0 }

    it 'does not apply the flat amount' do
      expect(apply_graduated_service.amount).to eq(0)
    end
  end

  context 'when aggregation is 1' do
    let(:aggregation) { 1 }

    it 'applies a unit amount for 1 and the flat rate for 1' do
      expect(apply_graduated_service.amount).to eq(12)
    end
  end

  context 'when aggregation is 10' do
    let(:aggregation) { 10 }

    it 'applies all unit amount for top bound' do
      expect(apply_graduated_service.amount).to eq(102)
    end
  end

  context 'when aggregation is 11' do
    let(:aggregation) { 11 }

    it 'applies next range flat amount for the next step' do
      expect(apply_graduated_service.amount).to eq(110)
    end
  end

  context 'when aggregation is 12' do
    let(:aggregation) { 12 }

    it 'applies next unit amount for more unit in next step' do
      expect(apply_graduated_service.amount).to eq(115)
    end
  end

  context 'when aggregation is 21' do
    let(:aggregation) { 21 }

    it 'applies last unit amount for more unit in last step' do
      expect(apply_graduated_service.amount).to eq(163)
    end
  end
end
