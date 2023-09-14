# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::StandardService, type: :service do
  subject(:apply_standard_service) do
    described_class.apply(
      charge:,
      aggregation_result:,
      properties: charge.properties,
    )
  end

  before do
    aggregation_result.aggregation = aggregation
    aggregation_result.total_aggregated_units = total_aggregated_units if total_aggregated_units
  end

  let(:aggregation_result) { BaseService::Result.new }
  let(:aggregation) { 10 }
  let(:total_aggregated_units) { nil }

  let(:charge) do
    create(
      :standard_charge,
      charge_model: 'standard',
      properties: {
        amount: '500',
      },
    )
  end

  it 'applies the charge model to the value' do
    expect(apply_standard_service.amount).to eq(5000)
  end

  context 'when aggregation result contains total_aggregated_units' do
    let(:total_aggregated_units) { 10 }

    it 'assigns the total_aggregated_units to the result' do
      expect(apply_standard_service.total_aggregated_units).to eq(total_aggregated_units)
    end
  end
end
