# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::PercentageService, type: :service do
  subject(:apply_percentage_service) do
    described_class.apply(charge: charge, aggregation_result: aggregation_result)
  end

  before do
    aggregation_result.aggregation = aggregation
    aggregation_result.count = 4
    aggregation_result.options = { running_total: [50, 150, 400] }
  end

  let(:aggregation_result) { BaseService::Result.new }
  let(:fixed_amount) { '2.0' }
  let(:aggregation) { 800 }
  let(:free_units_per_events) { 3 }
  let(:free_units_per_total_aggregation) { '250.0' }

  let(:expected_percentage_amount) { (800 - 250) * (1.3 / 100) }
  let(:expected_fixed_amount) { (4 - 2) * 2.0 }

  let(:charge) do
    create(
      :percentage_charge,
      properties: {
        rate: '1.3',
        fixed_amount: fixed_amount,
        free_units_per_events: free_units_per_events,
        free_units_per_total_aggregation: free_units_per_total_aggregation,
      },
    )
  end

  context 'when aggregation value is 0' do
    let(:aggregation) { 0 }

    it 'returns 0' do
      expect(apply_percentage_service.amount).to eq(0)
    end
  end

  context 'when fixed amount value is 0' do
    it 'returns expected percentage amount' do
      expect(apply_percentage_service.amount).to eq(
        (expected_percentage_amount + expected_fixed_amount)
      )
    end
  end

  context 'when free_units_per_total_aggregation > last running total' do
    let(:free_units_per_total_aggregation) { '500.0' }
    let(:expected_percentage_amount) { (800 - 400) * (1.3 / 100) }
    let(:expected_fixed_amount) { (4 - 3) * 2.0 }

    it 'returns expected percentage amount based on last running total' do
      expect(apply_percentage_service.amount).to eq(
        (expected_percentage_amount + expected_fixed_amount)
      )
    end
  end
end
