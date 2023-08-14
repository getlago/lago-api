# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::GraduatedPercentageService, type: :service do
  subject(:apply_graduated_percentage_service) do
    described_class.apply(
      charge:,
      aggregation_result:,
      properties: charge.properties,
    )
  end

  let(:aggregation_result) do
    BaseService::Result.new.tap do |r|
      r.aggregation = aggregation
      r.count = aggregation_count
    end
  end

  let(:charge) do
    create(
      :graduated_percentage_charge,
      properties: {
        graduated_percentage_ranges: [
          {
            from_value: 0,
            to_value: 10,
            flat_amount: '200',
            fixed_amount: '0.5',
            rate: '1',
          },
          {
            from_value: 11,
            to_value: 20,
            flat_amount: '300',
            fixed_amount: '0.4',
            rate: '2',
          },
          {
            from_value: 21,
            to_value: nil,
            flat_amount: '400',
            fixed_amount: '0.3',
            rate: '3',
          },
        ],
      },
    )
  end

  context 'when aggregation is 0' do
    let(:aggregation) { 0 }
    let(:aggregation_count) { 0 }

    it 'does not apply the flat amount' do
      expect(apply_graduated_percentage_service.amount).to eq(0)
    end
  end

  context 'when aggregation is 1' do
    let(:aggregation) { 1 }
    let(:aggregation_count) { 1 }

    it 'applies a unit amount for 1 and the flat rate for 1' do
      # NOTE: 200 + 1 * 0.01 + 1 * 0.5
      expect(apply_graduated_percentage_service.amount).to eq(200.51)
    end
  end

  context 'when aggregation is 10' do
    let(:aggregation) { 10 }
    let(:aggregation_count) { 1 }

    it 'applies all unit amount up to the top bound' do
      # NOTE: 200 + 10 * 0.01 + 1 * 0.5
      expect(apply_graduated_percentage_service.amount).to eq(200.6)
    end
  end

  context 'when aggregation is 11' do
    let(:aggregation) { 11 }
    let(:aggregation_count) { 1 }

    it 'applies next ranges flat amount' do
      # NOTE: 200 + 300 + 10 * 0.01 + 1 * 0.02 + 1 * 0.4
      expect(apply_graduated_percentage_service.amount).to eq(500.52)
    end
  end

  context 'when aggregation is 12' do
    let(:aggregation) { 12 }
    let(:aggregation_count) { 1 }

    it 'applies next ranges flat amount and range units amount' do
      # NOTE: 200 + 300 + 10 * 0.01 + 2 * 0.02 + 1 * 0.4
      expect(apply_graduated_percentage_service.amount).to eq(500.54)
    end
  end

  context 'when aggregation is 21' do
    let(:aggregation) { 21 }
    let(:aggregation_count) { 1 }

    it 'applies last unit amount for more unit in last step' do
      # NOTE: 200 + 300 + 400 + 10 * 0.01 + 10 * 0.02 + 1 * 0.03 + 1 * 0.3
      expect(apply_graduated_percentage_service.amount).to eq(900.63)
    end
  end
end
